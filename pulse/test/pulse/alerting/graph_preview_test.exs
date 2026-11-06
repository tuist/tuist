defmodule Pulse.Alerting.GraphPreviewTest do
  use Pulse.Test.Case, async: true

  import Kernel, except: [binding: 1]

  alias Pulse.Alerting.GraphPreview
  alias Pulse.PromQL.Evaluator
  alias Pulse.Record.MetricSample
  alias Pulse.Runtime
  alias Pulse.Storage
  alias Pulse.Storage.Memory

  defp graph do
    %{
      "condition" => "C",
      "data" => [
        %{
          "refId" => "A",
          "datasourceUid" => "original-prom",
          "relativeTimeRange" => %{"from" => 600, "to" => 0},
          "model" => %{"instant" => true, "range" => false, "expr" => "sum by (pod) (errors)"}
        },
        %{
          "refId" => "B",
          "datasourceUid" => "original-prom",
          "model" => %{"instant" => true, "expr" => "sum by (pod) (requests)"}
        },
        %{
          "refId" => "C",
          "datasourceUid" => "__expr__",
          "model" => %{"type" => "math", "expression" => "$A > 2 && $B > 100"}
        }
      ]
    }
  end

  defp binding(tenant), do: %{"tenant" => tenant, "uid" => "original-prom", "type" => "native_promql"}

  setup do
    Memory.reset()
    Runtime.put_env(:pulse, Pulse.Alerting, source_bindings: [binding("acme")])

    for {tenant, name, value} <- [{"acme", "errors", 3.0}, {"acme", "requests", 200.0}, {"beta", "errors", 0.0}] do
      assert :ok =
               Storage.append(:metrics, tenant, [
                 %MetricSample{
                   series_id: 1,
                   timestamp_ns: 100_000_000_000,
                   value: value,
                   labels: %{"__name__" => name, "pod" => "one"}
                 }
               ])
    end

    :ok
  end

  test "explicit bindings preview native tenant sources without declaring rule executability" do
    assert {:ok, preview} = GraphPreview.preview(graph(), "acme", 100_000_000_000)
    assert preview["result"] == %{"type" => "numbers", "frames" => [%{"labels" => %{"pod" => "one"}, "value" => "1.0"}]}
    assert preview["executable"] == false
    assert preview["migrated"] == false
    assert "source_residency_and_recording_freshness_unproven" in preview["blockers"]
    assert {:error, {:graph_source, _, :unbound_source}} = GraphPreview.preview(graph(), "beta", 100_000_000_000)
  end

  test "missing native data is a graph result, not proof of source residency or healthy lifecycle" do
    assert {:ok, preview} = GraphPreview.preview(graph(), "acme", 999_000_000_000)
    assert preview["result"] == %{"type" => "numbers", "frames" => []}
    refute Map.has_key?(preview, "health")
  end

  test "bindings are closed, bounded, unique and cannot add external destinations" do
    assert :ok = GraphPreview.bindings([binding("acme"), binding("beta")])

    for bindings <- [
          [binding("acme"), binding("acme")],
          [Map.put(binding("acme"), "url", "https://example.com")],
          [Map.put(binding("acme"), "type", "clickhouse")],
          [Map.put(binding("acme"), "tenant", "../beta")],
          List.duplicate(binding("acme"), 257),
          nil
        ] do
      assert {:error, :invalid_source_bindings} = GraphPreview.bindings(bindings)
    end
  end

  test "unsupported source kinds, range queries and invalid windows fail before querying" do
    source = hd(graph()["data"])

    for changed <- [
          Map.put(source, "source_type", "clickhouse"),
          put_in(source, ["model", "instant"], false),
          put_in(source, ["model", "range"], true),
          put_in(source, ["model", "timeShift"], "1d"),
          put_in(source, ["model", "datasource"], %{"type" => "prometheus", "uid" => "other"}),
          put_in(source, ["model", "unknownSemanticField"], true),
          Map.put(source, "model", "malformed")
        ] do
      original = Map.put(graph(), "data", [changed | tl(graph()["data"])])

      assert {:error, {:graph_source, "A", :unsupported_source_query}} =
               GraphPreview.preview(original, "acme", 100_000_000_000)
    end

    changed = Map.put(source, "relativeTimeRange", %{"from" => 0, "to" => 1})

    assert {:error, {:graph_source, "A", :invalid_source_time}} =
             GraphPreview.preview(Map.put(graph(), "data", [changed | tl(graph()["data"])]), "acme", 100_000_000_000)
  end

  test "response expansion counts repeated labels before encoding the preview" do
    samples =
      for i <- 1..400,
          do: %MetricSample{
            series_id: 1,
            timestamp_ns: 100_000_000_000,
            value: 1.0,
            labels: %{"__name__" => "many", "pod" => String.pad_leading(Integer.to_string(i), 500, "x")}
          }

    assert :ok = Storage.append(:metrics, "acme", samples)
    source = hd(graph()["data"]) |> put_in(["model", "expr"], "many")
    original = %{"data" => [source], "condition" => "A"}
    assert {:error, :expression_result_limit} = GraphPreview.preview(original, "acme", 100_000_000_000)
  end

  test "all graph queries share the sample budget and errors never produce partial preview" do
    Runtime.put_env(:pulse, Evaluator, max_samples: 1)
    assert {:error, :query_sample_limit} = GraphPreview.preview(graph(), "acme", 100_000_000_000)
  end
end
