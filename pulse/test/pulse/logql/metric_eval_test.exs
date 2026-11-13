defmodule Pulse.LogQL.MetricEvalTest do
  use Pulse.Test.Case, async: true

  alias Pulse.LogQL.AST.NumberLit
  alias Pulse.LogQL.Evaluator
  alias Pulse.LogQL.Parser
  alias Pulse.Record.Log
  alias Pulse.Storage
  alias Pulse.Storage.Memory

  setup do
    Memory.reset()
    :ok
  end

  defp log(tenant, records), do: :ok = Storage.append(:logs, tenant, records)
  defp record(fields), do: struct!(Log, Map.new(fields))

  defp run(query, opts) do
    {:ok, ast} = Parser.parse(query)
    Evaluator.evaluate_metric(ast, "acme", opts)
  end

  test "matrix step limits apply before allocation, including scalar expressions" do
    maximum = Pulse.QueryLimits.max_evaluation_steps()
    expr = %NumberLit{value: 1}

    assert {:ok, {:matrix, [{%{}, samples}]}} =
             Evaluator.evaluate_metric(expr, "acme", %{start_ts_ns: 0, end_ts_ns: maximum - 1, step_ns: 1})

    assert length(samples) == maximum

    for finish <- [maximum, 9_000_000_000_000_000_000] do
      assert {:error, :invalid_range_or_too_many_steps} =
               Evaluator.evaluate_metric(expr, "acme", %{start_ts_ns: 0, end_ts_ns: finish, step_ns: 1})
    end
  end

  describe "count_over_time (vector)" do
    test "counts entries in the range" do
      # Timestamps at 1s, 2s, 3s (in ns)
      log("acme", [
        record(timestamp_ns: 1_000_000_000, service: "api", body: "a"),
        record(timestamp_ns: 2_000_000_000, service: "api", body: "b"),
        record(timestamp_ns: 3_000_000_000, service: "api", body: "c")
      ])

      # Evaluate at t=3s with [5m] range → sees all 3
      assert {:ok, {:vector, [{_labels, {_ts, 3.0}}]}} =
               run("count_over_time({service=\"api\"}[5m])", %{end_ts_ns: 3_000_000_000})
    end
  end

  describe "rate (vector)" do
    test "returns entries per second" do
      log("acme", [
        record(timestamp_ns: 1_000_000_000, service: "api", body: "a"),
        record(timestamp_ns: 2_000_000_000, service: "api", body: "b")
      ])

      # 2 entries over 1 minute = 2/60 ≈ 0.033
      assert {:ok, {:vector, [{_labels, {_ts, value}}]}} =
               run("rate({service=\"api\"}[1m])", %{end_ts_ns: 60_000_000_000})

      assert_in_delta value, 2 / 60, 0.001
    end
  end

  describe "sum by grouping" do
    test "sums counts across services and groups by env" do
      log("acme", [
        record(timestamp_ns: 1_000_000_000, service: "api", body: "a", resource: %{"env" => "prod"}),
        record(timestamp_ns: 2_000_000_000, service: "db", body: "b", resource: %{"env" => "prod"}),
        record(timestamp_ns: 3_000_000_000, service: "api", body: "c", resource: %{"env" => "dev"})
      ])

      assert {:ok, {:vector, series}} =
               run("sum by (env) (count_over_time({service=~\"api|db\"}[5m]))", %{
                 end_ts_ns: 3_000_000_000
               })

      by_env =
        Map.new(series, fn {labels, {_ts, v}} ->
          {labels["env"], v}
        end)

      assert by_env == %{"prod" => 2.0, "dev" => 1.0}
    end
  end

  describe "topk" do
    test "returns the k highest series" do
      log("acme", [
        record(timestamp_ns: 1_000_000_000, service: "a", body: "1"),
        record(timestamp_ns: 2_000_000_000, service: "b", body: "1"),
        record(timestamp_ns: 3_000_000_000, service: "b", body: "2"),
        record(timestamp_ns: 4_000_000_000, service: "c", body: "1"),
        record(timestamp_ns: 5_000_000_000, service: "c", body: "2"),
        record(timestamp_ns: 6_000_000_000, service: "c", body: "3")
      ])

      # count_over_time returns 3 for c, 2 for b, 1 for a → topk(2) drops a
      assert {:ok, {:vector, series}} =
               run("topk(2, count_over_time({service=~\"a|b|c\"}[10m]))", %{end_ts_ns: 6_000_000_000})

      services = Enum.map(series, fn {_labels, {_ts, _v}} -> nil end)
      assert length(services) == 2
    end
  end

  describe "binary op with scalar" do
    test "count > 2 yields 3.0 or drop" do
      log("acme", [
        record(timestamp_ns: 1_000_000_000, service: "a", body: "1"),
        record(timestamp_ns: 2_000_000_000, service: "a", body: "2"),
        record(timestamp_ns: 3_000_000_000, service: "a", body: "3")
      ])

      # Filter comparison: count_over_time > 2 → 3.0 for a
      assert {:ok, {:vector, series}} =
               run("count_over_time({service=\"a\"}[10m]) > 2", %{end_ts_ns: 3_000_000_000})

      assert [{_labels, {_ts, 3.0}}] = series
    end

    test "bool comparison returns 0/1" do
      log("acme", [
        record(timestamp_ns: 1_000_000_000, service: "a", body: "x"),
        record(timestamp_ns: 2_000_000_000, service: "a", body: "y")
      ])

      assert {:ok, {:vector, [{_l, {_t, 1.0}}]}} =
               run("count_over_time({service=\"a\"}[10m]) > bool 1", %{end_ts_ns: 2_000_000_000})
    end
  end

  describe "matrix (range with step)" do
    test "count_over_time bucketed at step intervals" do
      # Log entries every second from 1s to 5s
      log(
        "acme",
        for i <- 1..5 do
          record(timestamp_ns: i * 1_000_000_000, service: "a", body: "l#{i}")
        end
      )

      # Range 1s at step 1s over [1s, 5s]: at each t, count entries in (t-1s, t]
      assert {:ok, {:matrix, series}} =
               run("count_over_time({service=\"a\"}[1s])", %{
                 start_ts_ns: 1_000_000_000,
                 end_ts_ns: 5_000_000_000,
                 step_ns: 1_000_000_000
               })

      assert [{_labels, samples}] = series
      # Each 1-second bucket should have 1 entry
      assert length(samples) == 5
      Enum.each(samples, fn {_ts, v} -> assert v == 1.0 end)
    end

    test "matrix samples carry the real step timestamp (regression: index leak)" do
      log(
        "acme",
        for i <- 1..3 do
          record(timestamp_ns: i * 1_000_000_000, service: "a", body: "x")
        end
      )

      assert {:ok, {:matrix, [{_labels, samples}]}} =
               run("count_over_time({service=\"a\"}[1s])", %{
                 start_ts_ns: 1_000_000_000,
                 end_ts_ns: 3_000_000_000,
                 step_ns: 1_000_000_000
               })

      ts_list = Enum.map(samples, fn {ts, _} -> ts end)
      # Expect real Unix-nanosecond timestamps, not 0/1/2.
      assert ts_list == [1_000_000_000, 2_000_000_000, 3_000_000_000]
    end
  end

  describe "binary op :drop handling" do
    test "un-boolean comparison drops non-matching series without crashing" do
      log("acme", [
        record(timestamp_ns: 1_000_000_000, service: "a", body: "1"),
        record(timestamp_ns: 2_000_000_000, service: "a", body: "2"),
        record(timestamp_ns: 3_000_000_000, service: "a", body: "3")
      ])

      # count_over_time returns 3.0 → 3.0 > 5 fails → :drop → empty series
      assert {:ok, {:vector, []}} =
               run("count_over_time({service=\"a\"}[10m]) > 5", %{end_ts_ns: 3_000_000_000})

      # 3.0 > 1 passes → keeps the value
      assert {:ok, {:vector, [{_labels, {_ts, 3.0}}]}} =
               run("count_over_time({service=\"a\"}[10m]) > 1", %{end_ts_ns: 3_000_000_000})
    end
  end

  describe "invalid regex" do
    test "returns a clear error instead of crashing" do
      assert {:error, {:invalid_regex, _source, _pattern, _reason}} =
               run("{service=~\"(\"}", %{end_ts_ns: 1_000_000_000})
    end
  end
end
