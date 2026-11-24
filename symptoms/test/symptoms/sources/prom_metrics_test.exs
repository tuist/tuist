Code.require_file("source_helpers.ex", __DIR__)

defmodule Symptoms.Sources.PromMetricsTest do
  use ExUnit.Case, async: true
  use Mimic

  import Symptoms.SourceHelpers

  alias Symptoms.Sources.PromMetrics
  alias Symptoms.Sources.PromMetrics.Entities

  @window %{start: 1_763_301_600, seconds: 60}

  @definitions [
    %{
      key: "ingress.tuist-dev.requests",
      phenomenon: :request_errors,
      role: :denominator,
      split: {"host", "tuist.dev"},
      units: "",
      promql: "REQ"
    },
    %{
      key: "ingress.tuist-dev.5xx",
      phenomenon: :request_errors,
      role: :numerator,
      split: {"host", "tuist.dev"},
      units: "",
      promql: "ERR"
    },
    %{
      key: "oban.process_build.available",
      phenomenon: :saturation,
      role: :backlog,
      split: {"queue", "process_build"},
      units: "",
      promql: "OBAN"
    },
    %{key: "postgres.replication_lag", phenomenon: :latency, role: :resource, split: nil, units: "", promql: "LAG"}
  ]

  defp reply("REQ"), do: vector([{%{"host" => "tuist.dev"}, 1000}, {%{"host" => "registry.tuist.dev"}, 50}])
  defp reply("ERR"), do: vector([{%{"host" => "tuist.dev"}, 30}, {%{"host" => "registry.tuist.dev"}, 0}])
  defp reply("OBAN"), do: vector([{%{"queue" => "process_build"}, 600}])
  defp reply("deriv((OBAN)[15m:1m])"), do: vector([{%{"queue" => "process_build"}, -2}])
  defp reply("LAG"), do: vector([])

  test "the default list is the replay manifest's 90 entities with PromQL" do
    entities = Entities.all()
    assert length(entities) == 90
    assert entities |> Enum.map(& &1.key) |> Enum.uniq() |> length() == 90
    assert Enum.all?(entities, &(is_binary(&1.promql) and &1.promql =~ "{"))

    manifest = Path.expand("../../../../.amp/in/replay-data/manifest.json", __DIR__)

    if File.exists?(manifest) do
      expected =
        manifest |> File.read!() |> Jason.decode!() |> Map.fetch!("entities") |> Map.new(&{&1["key"], &1["promql"]})

      assert Map.new(entities, &{&1.key, &1.promql}) == expected
    end
  end

  test "error share, level, backlog growth and time to drain against hour-of-week baselines" do
    stub_prometheus(&reply/1)
    test = self()

    opts =
      prom_opts(
        definitions: @definitions,
        unknown: &send(test, {:unknown, &1, &2}),
        baseline:
          baselines(%{
            {"metric.error_share", "ingress.tuist-dev"} => [0.01, 0.02, 0.03],
            {"metric.robust_residual", "oban.process_build.available"} => [100, 200, 300, 400],
            {"metric.backlog_growth", "oban.process_build.available"} => [0, 0, 0]
          })
      )

    assert {:ok, records} = PromMetrics.collect(@window, opts)
    by_source = Map.new(records, &{&1.source, &1})

    # Share 0.03; median 0.02, MAD 0.01 → (0.03 - 0.02) / 0.014826.
    share = by_source["metric.error_share"]
    assert share.entity.key == "ingress.tuist-dev"
    assert_in_delta share.statistic, 0.01 / 0.014826, 1.0e-9
    # 30 errors per 5 minutes.
    assert share.impact == %{unit: "failed_requests_per_min", rate: 6.0}

    # 600 against [100..400]: median 250, deviations 150, 50, 50, 150 → MAD 100.
    assert_in_delta by_source["metric.robust_residual"].statistic, 350 / 148.26, 1.0e-9
    # Slope -2 against an all-zero baseline: MAD and mean deviation 0 → scale 1.
    assert_in_delta by_source["metric.backlog_growth"].statistic, -2.0, 1.0e-12
    # 600 jobs draining at 2 per second.
    assert by_source["metric.time_to_drain"].statistic == 300.0

    # The replication lag series is missing: unknown, not zero.
    assert_received {:unknown, "metric", [%{key: "postgres.replication_lag"}]}
  end

  test "time to drain" do
    assert PromMetrics.time_to_drain(0, -1) == 0.0
    assert PromMetrics.time_to_drain(100, 1) == 86_400.0
    assert PromMetrics.time_to_drain(1.0e9, -1) == 86_400.0
  end

  test "an unreachable Mimir is unknown for every entity" do
    stub_prometheus(fn _ -> {:error, 502} end)
    assert {:unknown, entities} = PromMetrics.collect(@window, prom_opts(definitions: @definitions))

    assert entities |> Enum.map(& &1.key) |> Enum.sort() == [
             "ingress.tuist-dev",
             "oban.process_build.available",
             "postgres.replication_lag"
           ]
  end

  test "history for the hour-of-week baseline" do
    stub_prometheus(fn
      "REQ" -> matrix([{%{"host" => "tuist.dev"}, [{1000, 100}, {1300, 0}]}])
      "ERR" -> matrix([{%{"host" => "tuist.dev"}, [{1000, 5}, {1300, 0}]}])
    end)

    assert {:ok, [point]} =
             PromMetrics.history(
               "ingress.tuist-dev",
               "metric.error_share",
               2_000_000,
               prom_opts(definitions: @definitions)
             )

    assert point == %{window_start: DateTime.from_unix!(1000), statistic: 0.05}
  end

  test "inapplicable history streams are empty without making a query; real errors remain errors" do
    # The baseline worker requests its three known streams for each entity.
    # A standalone level has no share/growth; a paired numerator no level.
    opts = prom_opts(definitions: @definitions)
    stub_prometheus(fn _ -> flunk("inapplicable history must not query Prometheus") end)

    for {key, stream} <- [
          {"postgres.replication_lag", "metric.error_share"},
          {"postgres.replication_lag", "metric.backlog_growth"},
          {"ingress.tuist-dev", "metric.robust_residual"},
          {"ingress.tuist-dev", "metric.backlog_growth"}
        ] do
      assert {:ok, []} = PromMetrics.history(key, stream, 2_000_000, opts)
    end

    assert {:error, :unknown_entity} = PromMetrics.history("missing", "metric.robust_residual", 2_000_000, opts)

    stub_prometheus(fn _ -> {:error, 502} end)
    assert {:error, _} = PromMetrics.history("postgres.replication_lag", "metric.robust_residual", 2_000_000, opts)
    assert {:error, _} = PromMetrics.history("ingress.tuist-dev", "metric.error_share", 2_000_000, opts)
    assert {:error, _} = PromMetrics.history("oban.process_build.available", "metric.backlog_growth", 2_000_000, opts)
  end
end
