defmodule Pulse.LogQL.RangeGroupingTest do
  use Pulse.Test.Case, async: true

  alias Pulse.LogQL.Evaluator
  alias Pulse.LogQL.Parser
  alias Pulse.LogQL.QueryValidation
  alias Pulse.Record.Log
  alias Pulse.Storage
  alias Pulse.Storage.Memory

  setup do
    Memory.reset()

    records =
      for {env, pod, value} <- [
            {"prod", "one", 1000},
            {"prod", "two", 4000},
            {"dev", "three", 2000},
            {"dev", "four", 3000}
          ] do
        %Log{
          timestamp_ns: 10_000_000_000,
          service: "web",
          body: "app_environment=#{env} lcp=#{value}",
          resource: %{"pod" => pod}
        }
      end

    assert :ok = Storage.append(:logs, "acme", records)
    :ok
  end

  defp run(query, opts \\ %{end_ts_ns: 10_000_000_000}) do
    with {:ok, ast} <- Parser.parse(query), do: Evaluator.evaluate_metric(ast, "acme", opts)
  end

  test "range grouping combines observations across source streams before interpolating" do
    assert {:ok, {:vector, series}} =
             run(
               ~s'quantile_over_time(0.5, {service_name="web"} | logfmt | unwrap lcp [5m]) by (app_environment) / 1000'
             )

    assert Map.new(series) == %{
             %{"app_environment" => "prod"} => {10_000_000_000, 2.5},
             %{"app_environment" => "dev"} => {10_000_000_000, 2.5}
           }

    assert {:ok, {:matrix, matrix}} =
             run(~s'quantile_over_time(0.5, {service_name="web"} | logfmt | unwrap lcp [5m]) by (app_environment)', %{
               start_ts_ns: 10_000_000_000,
               end_ts_ns: 11_000_000_000,
               step_ns: 1_000_000_000
             })

    assert Enum.all?(matrix, fn {_labels, samples} ->
             samples == [{10_000_000_000, 2500.0}, {11_000_000_000, 2500.0}]
           end)
  end

  test "unwrapped values do not become series identity without explicit grouping" do
    assert :ok =
             Storage.append(:logs, "acme", [
               %Log{timestamp_ns: 10, service: "same", body: "value=1"},
               %Log{timestamp_ns: 11, service: "same", body: "value=4"}
             ])

    assert {:ok, {:vector, [{labels, {12, 2.5}}]}} =
             run(~s'quantile_over_time(0.5, {service_name="same"} | logfmt | unwrap value [1m])', %{end_ts_ns: 12})

    refute Map.has_key?(labels, "value")
  end

  test "unsupported range semantics reject instead of silently ignoring modifiers or counting counters" do
    for query <- [
          ~s'count_over_time({service="web"}[5m]) by (pod)',
          ~s'rate_counter({service="web"}[5m])',
          ~s'rate_counter({service="web"} | logfmt | unwrap lcp [5m]) by (pod)',
          ~s'count_over_time({service="web"}[5m] @ 10)',
          ~s'quantile_over_time({service="web"} | logfmt | unwrap lcp [5m])',
          ~s'sum_over_time({service="web"}[5m])'
        ] do
      assert {:ok, ast} = Parser.parse(query)
      assert {:error, _} = QueryValidation.validate(ast)
      assert {:error, _} = Evaluator.evaluate_metric(ast, "acme", %{end_ts_ns: 10_000_000_000})
    end
  end

  test "vector aggregation keeps the requested timestamp, never epoch zero" do
    assert {:ok, {:vector, [{%{}, {10_000_000_000, 4.0}}]}} = run(~s'sum(count_over_time({service="web"}[5m]))')
  end

  test "all inventoried Loki sources parse and validate after range-grouping support" do
    snapshot = Pulse.JSON.decode!(File.read!("plans/alerting/grafana-rule-inventory.json"))
    nodes = for rule <- snapshot["rules"], node <- rule["data"], node["source_type"] == "loki", do: node
    assert length(nodes) == 16

    for node <- nodes do
      assert {:ok, ast} = Parser.parse(node["model"]["expr"])
      assert :ok = QueryValidation.validate(ast)
    end
  end

  test "byte, depth and AST budgets apply before unbounded parser work and ignore quoted regex parentheses" do
    assert {:error, :query_expression_limit} = Parser.parse(String.duplicate(" ", 16_385))

    assert {:error, :query_expression_limit} =
             Parser.parse(
               String.duplicate("sum(", 65) <> ~s'count_over_time({service="web"}[1m])' <> String.duplicate(")", 65)
             )

    assert {:error, :query_expression_limit} = Parser.parse(Enum.join(List.duplicate("1", 300), "+"))
    assert {:ok, _} = Parser.parse(~s'{service="web"} |= "#{String.duplicate("(", 128)}"')
  end
end
