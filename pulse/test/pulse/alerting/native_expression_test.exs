defmodule Pulse.Alerting.NativeExpressionTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Alerting.{NativeExpression, Rule}
  alias Pulse.Record.MetricSample
  alias Pulse.Storage

  defp rule do
    %{
      "kind" => "expression_threshold",
      "name" => "Combined condition",
      "sources" => [
        %{"ref" => "errors", "language" => "logql", "query" => ~s'sum(count_over_time({service="api"}[5m]))'},
        %{"ref" => "requests", "language" => "promql", "query" => "sum(requests)"}
      ],
      "expression" => "$errors > 0 && $requests > 100",
      "threshold" => %{"op" => "gt", "value" => 0}
    }
  end

  test "native definitions are disabled by default, closed and fully bound" do
    assert {:ok, validated} = Rule.validate(rule())
    assert validated["enabled"] == false
    assert validated["no_data_policy"] == "keep_last"
    assert Rule.classification(validated) == []

    invalid = [
      Map.put(rule(), "query", "up"),
      Map.put(rule(), "expression", "$missing > 0"),
      Map.put(rule(), "expression", "$errors > 0"),
      Map.put(rule(), "sources", []),
      update_in(rule(), ["sources"], fn [a, b] -> [a, Map.put(b, "query", "requests[5m]")] end),
      update_in(rule(), ["sources"], fn [a, b] -> [a, Map.put(b, "empty_value", 1)] end),
      Map.put(rule(), "sources", List.duplicate(hd(rule()["sources"]), 17)),
      put_in(rule(), ["sources"], [%{"ref" => "errors", "language" => "logql", "query" => ~s'{service="api"}'}]),
      update_in(rule(), ["sources"], fn [a, b] -> [a, Map.put(b, "tenant", "other")] end),
      update_in(rule(), ["sources"], fn [a, b] -> [a, Map.put(b, "ref", "errors")] end),
      update_in(rule(), ["sources"], fn [a, b] -> [a, Map.put(b, "url", "https://external.invalid")] end),
      update_in(rule(), ["sources"], fn [a, b] -> [a, Map.put(b, "language", "clickhouse")] end),
      update_in(rule(), ["sources"], fn [a, b] -> [a, Map.put(b, "query", "invalid (")] end)
    ]

    for definition <- invalid, do: assert({:error, :invalid_rule} = Rule.validate(definition))
  end

  test "only explicitly authored, successful fully empty vectors become scalar zero" do
    assert :ok =
             Storage.append(:metrics, "local", [
               %MetricSample{timestamp_ns: 10, value: 200.0, labels: %{"__name__" => "requests", "service" => "api"}}
             ])

    definition = put_in(rule(), ["sources", Access.at(1), "query"], "requests")
    assert {:ok, validated} = Rule.validate(definition)
    assert {:ok, %{"data" => %{"result" => []}}} = NativeExpression.query(validated, "local", %{end_ts_ns: 10})
    definition = put_in(definition, ["sources", Access.at(0), "empty_value"], 0)
    assert {:ok, validated} = Rule.validate(definition)
    assert {:ok, %{"data" => %{"result" => [sample]}}} = NativeExpression.query(validated, "local", %{end_ts_ns: 10})
    assert sample["value"] == [0, "0.0"]
    assert sample["metric"]["service"] == "api"
    assert {:ok, validated} = Rule.validate(Map.put(definition, "expression", "$errors > 0 || $requests > 100"))
    assert {:ok, %{"data" => %{"result" => [sample]}}} = NativeExpression.query(validated, "local", %{end_ts_ns: 10})
    assert sample["value"] == [0, "1.0"]
  end

  test "incompatible labels cannot silently become an unlabeled alert" do
    samples = [
      %MetricSample{timestamp_ns: 10, value: 1.0, labels: %{"__name__" => "left", "service" => "api"}},
      %MetricSample{timestamp_ns: 10, value: 2.0, labels: %{"__name__" => "right", "service" => "cache"}}
    ]

    assert :ok = Storage.append(:metrics, "local", samples)

    definition =
      Map.merge(rule(), %{
        "sources" => [
          %{"ref" => "a", "language" => "promql", "query" => "left"},
          %{"ref" => "b", "language" => "promql", "query" => "right"}
        ],
        "expression" => "$a + $b"
      })

    assert {:ok, validated} = Rule.validate(definition)
    assert {:error, :expression_label_loss} = NativeExpression.query(validated, "local", %{end_ts_ns: 10})
  end

  test "scalar broadcasts are explicit and preserve native vector labels" do
    assert :ok =
             Storage.append(:metrics, "local", [
               %MetricSample{timestamp_ns: 10, value: 200.0, labels: %{"__name__" => "requests", "service" => "api"}}
             ])

    definition =
      Map.merge(rule(), %{
        "sources" => [
          %{"ref" => "requests", "language" => "promql", "query" => "requests"},
          %{"ref" => "minimum", "language" => "promql", "query" => "100"}
        ],
        "expression" => "$requests > $minimum"
      })

    assert {:ok, validated} = Rule.validate(definition)
    assert {:ok, %{"data" => %{"result" => [sample]}}} = NativeExpression.query(validated, "local", %{end_ts_ns: 10})
    assert sample["metric"]["service"] == "api"
    assert sample["value"] == [0, "1.0"]
  end
end
