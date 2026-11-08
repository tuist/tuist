defmodule Pulse.LogQL.StreamedMetricParityTest do
  # Streamed range evaluation must answer exactly like the materializing
  # evaluator it replaced, including unwrap failures and equal timestamps.
  use Pulse.Test.Case, async: true

  alias Pulse.LogQL.MetricEval
  alias Pulse.LogQL.Parser
  alias Pulse.LogQL.QueryValidation
  alias Pulse.Record.Log
  alias Pulse.Storage
  alias Pulse.Test.MetricEvalReference

  @second 1_000_000_000

  defp records(tenant) do
    records =
      for i <- 1..300 do
        # Coarse timestamps make equal-time entries common.
        ts = Enum.random(0..120) * @second
        dur = Enum.random(["#{Enum.random(1..500)}", "#{Enum.random(1..500)}", "oops", "", nil])
        body = "level=info " <> if(dur, do: "dur=#{dur} ", else: "") <> "code=#{Enum.random([200, 500])} n=#{i}"

        %Log{
          timestamp_ns: ts,
          observed_timestamp_ns: Enum.random([nil, ts + i]),
          service: Enum.random(["api", "web"]),
          body: body,
          resource: %{"app" => Enum.random(["a", "b"]), "pod" => Enum.random(["p1", "p2", "p3"])}
        }
      end

    :ok = Storage.append(:logs, tenant, records)
  end

  defp query do
    unwrap? = :rand.uniform(2) == 1

    op =
      Enum.random(
        if(unwrap?,
          do: ~w(sum_over_time avg_over_time min_over_time max_over_time first_over_time last_over_time
                 stddev_over_time stdvar_over_time quantile_over_time absent_over_time rate),
          else: ~w(count_over_time rate bytes_over_time bytes_rate absent_over_time)
        )
      )

    pipeline = if unwrap?, do: ~s{| logfmt | dur != "oops" or code="500" | unwrap dur}, else: ~s{|= "level"}
    selector = Enum.random([~s/{app=~"a|b"}/, ~s/{app="a"}/, ~s/{service="api", pod!="p3"}/])
    range = Enum.random(["10s", "30s", "1m"])
    offset = Enum.random(["", " offset 15s"])
    param = if op == "quantile_over_time", do: "0.9, ", else: ""

    grouping =
      if op in ~w(avg_over_time min_over_time max_over_time first_over_time last_over_time stddev_over_time
                  stdvar_over_time quantile_over_time) and :rand.uniform(3) == 1,
        do: " by (pod)",
        else: ""

    inner = "#{op}(#{param}#{selector} #{pipeline} [#{range}]#{offset})#{grouping}"

    case :rand.uniform(3) do
      1 -> "sum by (app) (#{inner})"
      2 -> "max(#{inner})"
      _ -> inner
    end
  end

  defp evaluate(module, ast, tenant, opts) do
    Process.delete(:promql_budget)
    Process.delete(:promql_deadline_ms)
    module.evaluate(ast, tenant, opts)
  end

  defp canonical({:ok, {kind, series}}),
    do: {:ok, kind, series |> Enum.map(fn {labels, samples} -> {labels, approx(samples)} end) |> Enum.sort()}

  defp canonical(other), do: other

  defp approx(samples) when is_list(samples), do: Enum.map(samples, fn {ts, v} -> {ts, approx(v)} end)
  defp approx({ts, v}), do: {ts, approx(v)}
  defp approx(v) when is_float(v), do: Float.round(v, 9)
  defp approx(v), do: v

  test "reset errors retain distinct ordinary details through materialized grouping" do
    tenant = "error-ownership-model"

    assert :ok =
             Storage.append(:logs, tenant, [
               %Log{timestamp_ns: 10 * @second, body: "{", resource: %{"app" => "a"}, attributes: %{"n" => "7"}}
             ])

    for stages <- [
          ~s/| json | label_format __error_details__="mine" | drop __error__/,
          ~s/| json | label_format __error_details__="mine" | drop __error__,__error_details__/,
          ~s/| json | label_format __error_details__="mine" | label_format saved=__error_details__ | drop __error__,__error_details__/
        ] do
      {:ok, ast} = Parser.parse(~s/first_over_time({app="a"} #{stages} | unwrap n [1m]) by (__error_details__)/)
      expected_details = if stages =~ "saved=", do: %{}, else: %{"__error_details__" => "mine"}
      at = 30 * @second

      for module <- [MetricEval, MetricEvalReference] do
        assert {:ok, {:vector, [{^expected_details, {^at, 7.0}}]}} =
                 evaluate(module, ast, tenant, %{end_ts_ns: 30 * @second})

        assert {:ok, {:matrix, [{^expected_details, [{^at, 7.0}]}]}} =
                 evaluate(module, ast, tenant, %{
                   start_ts_ns: 30 * @second,
                   end_ts_ns: 120 * @second,
                   step_ns: 90 * @second
                 })
      end
    end
  end

  test "the materializing model independently validates every selected first/last value, not fetched gaps" do
    tenant = "window-model"

    records =
      for {timestamp, value} <- [{5, "1"}, {15, "oops"}, {25, "3"}],
          do: %Log{timestamp_ns: timestamp * @second, body: "dur=#{value}", resource: %{"app" => "a"}}

    assert :ok = Storage.append(:logs, tenant, records)

    for op <- ["first_over_time", "last_over_time"] do
      {:ok, wide} = Parser.parse(~s/#{op}({app="a"} | logfmt | unwrap dur [1m])/)
      {:ok, narrow} = Parser.parse(~s/#{op}({app="a"} | logfmt | unwrap dur [10s])/)

      for module <- [MetricEval, MetricEvalReference] do
        assert {:error, :sample_extraction_error} = evaluate(module, wide, tenant, %{end_ts_ns: 30 * @second})

        assert {:error, :sample_extraction_error} =
                 evaluate(module, wide, tenant, %{
                   start_ts_ns: 10 * @second,
                   end_ts_ns: 30 * @second,
                   step_ns: 20 * @second
                 })

        assert {:ok, {:matrix, [{%{"app" => "a"}, [{10 * @second, 1.0}, {30 * @second, 3.0}]}]}} ==
                 evaluate(module, narrow, tenant, %{
                   start_ts_ns: 10 * @second,
                   end_ts_ns: 30 * @second,
                   step_ns: 20 * @second
                 })
      end
    end
  end

  # Keep the 150 comparisons and their aggregate data-coverage guard together;
  # allow for scheduler contention during the full concurrent CI suite.
  @tag timeout: 180_000
  test "random range aggregations match the materializing evaluator" do
    tenant = "streamed-parity-#{System.unique_integer([:positive])}"
    records(tenant)

    for _ <- 1..150 do
      text = query()
      {:ok, ast} = Parser.parse(text)
      assert :ok = QueryValidation.validate(ast)

      opts =
        Enum.random([
          %{start_ts_ns: 20 * @second, end_ts_ns: 120 * @second, step_ns: Enum.random([5, 15, 30]) * @second},
          %{end_ts_ns: Enum.random(30..130) * @second}
        ])

      expected = evaluate(MetricEvalReference, ast, tenant, opts)
      actual = evaluate(MetricEval, ast, tenant, opts)
      assert canonical(actual) == canonical(expected), "#{text} #{inspect(opts)}"

      send(
        self(),
        {:outcome,
         case actual do
           {:ok, {_, []}} -> :empty
           {:ok, _} -> :data
           {:error, e} -> e
         end}
      )
    end

    outcomes =
      for _ <- 1..150,
          do:
            (receive do
               {:outcome, o} -> o
             end)

    # Guard against a vacuous comparison: most queries must produce data.
    assert Enum.count(outcomes, &(&1 == :data)) >= 40
  end
end
