defmodule Pulse.Alerting.MixedGraphPreviewTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Alerting.GraphPreview
  alias Pulse.PromQL.Evaluator
  alias Pulse.Record.Log
  alias Pulse.Record.MetricSample
  alias Pulse.Runtime
  alias Pulse.Storage
  alias Pulse.Storage.Memory

  @now 100_000_000_000
  defp source do
    %{
      "refId" => "A",
      "source_type" => "loki",
      "datasourceUid" => "original-logs",
      "relativeTimeRange" => %{"from" => 600, "to" => 0},
      "model" => %{
        "queryType" => "instant",
        "datasource" => %{"type" => "loki", "uid" => "original-logs"},
        "expr" => ~s'quantile_over_time(0.5, {service="api"} | logfmt | unwrap x [1m]) by (pod) / 1000'
      }
    }
  end

  defp graph do
    %{
      "condition" => "C",
      "data" => [
        source(),
        %{
          "refId" => "B",
          "datasourceUid" => "original-prom",
          "model" => %{"instant" => true, "expr" => "sum by (pod) (requests)"}
        },
        %{
          "refId" => "C",
          "datasourceUid" => "__expr__",
          "model" => %{"type" => "math", "expression" => "$A > 2.5 && $B > 100"}
        }
      ]
    }
  end

  setup do
    Memory.reset()

    Runtime.put_env(:pulse, Pulse.Alerting,
      source_bindings: [
        %{"tenant" => "acme", "uid" => "original-logs", "type" => "native_logql"},
        %{"tenant" => "acme", "uid" => "original-prom", "type" => "native_promql"}
      ]
    )

    for {tenant, values} <- [{"acme", [1500, 4500]}, {"beta", [1, 2]}] do
      records =
        for value <- values,
            do: %Log{timestamp_ns: @now, service: "api", body: "x=#{value}", resource: %{"pod" => "one"}}

      assert :ok = Storage.append(:logs, tenant, records)
    end

    assert :ok =
             Storage.append(:metrics, "acme", [
               %MetricSample{
                 timestamp_ns: @now,
                 series_id: 1,
                 value: 200.0,
                 labels: %{"__name__" => "requests", "pod" => "one"}
               }
             ])

    :ok
  end

  @tag :loki_scalars_batch
  test "LogQL scalar sources remain scalars in expression previews" do
    scalar = put_in(source(), ["model", "expr"], "7 > 2")
    assert {:ok, result} = GraphPreview.preview(%{"condition" => "A", "data" => [scalar]}, "acme", @now)
    assert result["result"] == %{"type" => "scalar", "value" => "1.0"}
    assert result["executable"] == false
  end

  test "native logs and metrics join only in the authorized tenant and remain non-executable" do
    assert {:ok, result} = GraphPreview.preview(graph(), "acme", @now)
    assert result["result"] == %{"type" => "numbers", "frames" => [%{"labels" => %{"pod" => "one"}, "value" => "1.0"}]}
    assert result["executable"] == false
    assert result["migrated"] == false
    assert "source_frame_conversion_and_pipeline_parity_unproven" in result["blockers"]
    assert {:error, {:graph_source, _, :unbound_source}} = GraphPreview.preview(graph(), "beta", @now)
  end

  test "explicit Loki range resolution exposes sparse native series and strict last without gap filling" do
    assert :ok =
             Storage.append(:logs, "acme", [
               %Log{timestamp_ns: @now - 1_000_000_000, service: "range", body: "hello", resource: %{"pod" => "one"}},
               %Log{timestamp_ns: @now, service: "range", body: "hello", resource: %{"pod" => "one"}}
             ])

    ranged =
      source()
      |> Map.put("relativeTimeRange", %{"from" => 3, "to" => 0})
      |> Map.put("model", %{
        "queryType" => "range",
        "instant" => true,
        "intervalMs" => 1000,
        "expr" => ~s'sum by(pod)(count_over_time({service="range"}[1s]))'
      })

    original = %{"condition" => "A", "data" => [ranged]}
    assert {:ok, result} = GraphPreview.preview(original, "acme", @now)

    assert result["result"] == %{
             "type" => "series",
             "frames" => [
               %{"labels" => %{"pod" => "one"}, "points" => [["99000000000", "1.0"], ["100000000000", "1.0"]]}
             ]
           }

    reduced = %{
      "condition" => "R",
      "data" => [
        ranged,
        %{
          "refId" => "R",
          "datasourceUid" => "__expr__",
          "model" => %{"type" => "reduce", "expression" => "A", "reducer" => "last"}
        }
      ]
    }

    assert {:ok, last} = GraphPreview.preview(reduced, "acme", @now)
    assert last["result"] == %{"type" => "numbers", "frames" => [%{"labels" => %{"pod" => "one"}, "value" => "1.0"}]}
  end

  test "unknown semantics, mode, binding type or missing range resolution fail closed" do
    for model <- [
          %{"queryType" => "range", "expr" => "1"},
          %{"queryType" => "instant", "range" => true, "expr" => "1"},
          %{"queryType" => "instant", "expr" => "1", "datasource" => %{"type" => "prometheus"}},
          %{"queryType" => "instant", "expr" => "1", "unknownField" => true}
        ] do
      original = %{"condition" => "A", "data" => [Map.put(source(), "model", model)]}
      assert {:error, {:graph_source, "A", _}} = GraphPreview.preview(original, "acme", @now)
    end

    for node <- [
          put_in(source(), ["model", "datasource", "url"], "https://not-contacted.invalid"),
          Map.put(source(), "relativeTimeRange", %{"from" => 60, "to" => 0, "unknown" => true}),
          Map.put(source(), "relativeTimeRange", %{"from" => 0, "to" => 60})
        ] do
      assert {:error, {:graph_source, "A", _}} =
               GraphPreview.preview(%{"condition" => "A", "data" => [node]}, "acme", @now)
    end

    assert {:error, :unsupported_source_query} =
             GraphPreview.preview(
               %{"condition" => "A", "data" => [put_in(source(), ["model", "expr"], ~s'{service="api"}')]},
               "acme",
               @now
             )
  end

  test "kept log lines use the log sample quota and filtered lines still cost work" do
    Runtime.put_env(:pulse, Evaluator, max_log_samples: 0)
    assert {:error, :query_sample_limit} = GraphPreview.preview(graph(), "acme", @now)
    filtered = put_in(source(), ["model", "expr"], ~s'count_over_time({service="api"} | logfmt | x="never" [1m])')
    original = Map.put(graph(), "data", [filtered | tl(graph()["data"])])
    assert {:ok, _} = GraphPreview.preview(original, "acme", @now)
    Runtime.put_env(:pulse, Evaluator, max_work: 1)
    assert {:error, :query_work_limit} = GraphPreview.preview(original, "acme", @now)
  end

  test "nonempty pipeline error labels fail before grouping can discard them" do
    assert :ok =
             Storage.append(:logs, "acme", [
               %Log{
                 timestamp_ns: @now,
                 service: "api",
                 body: "x=3500",
                 resource: %{"pod" => "one"},
                 attributes: %{"__error__" => "JSONParserErr"}
               }
             ])

    assert {:error, :pipeline_error} = GraphPreview.preview(graph(), "acme", @now)

    filtered =
      put_in(
        source(),
        ["model", "expr"],
        ~s'quantile_over_time(0.5, {service="api"} | logfmt | __error__="" | unwrap x [1m]) by (pod) / 1000'
      )

    original = Map.put(graph(), "data", [filtered | tl(graph()["data"])])
    assert {:ok, result} = GraphPreview.preview(original, "acme", @now)
    assert hd(result["result"]["frames"])["value"] == "1.0"
  end

  test "source failures never become successful empty or partial graphs" do
    assert :ok =
             Storage.append(:logs, "acme", [
               %Log{timestamp_ns: @now, service: "api", body: "x=invalid", resource: %{"pod" => "one"}}
             ])

    assert {:error, :sample_extraction_error} = GraphPreview.preview(graph(), "acme", @now)
    bad = put_in(source(), ["model", "expr"], "$unsupported_macro")
    assert {:error, :invalid_logql} = GraphPreview.preview(%{"condition" => "A", "data" => [bad]}, "acme", @now)
  end
end
