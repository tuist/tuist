defmodule Pulse.Storage.S3.MetricPruningTest do
  @moduledoc """
  Manifest pruning for the selector shapes Grafana dashboards and alert rules
  send (`=~"$var"` expansions). Each segment is one remote-write-like batch;
  assertions count segment GETs, never wall-clock time, and compare every
  pruned result with unpruned memory storage.
  """
  use Pulse.Test.Case, async: true

  alias Pulse.PromQL.Evaluator
  alias Pulse.Record.MetricSample
  alias Pulse.Runtime
  alias Pulse.Storage
  alias Pulse.Storage.Memory
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Test.CompactionStore

  @moduletag timeout: 180_000
  @segments 60
  @time 2_000_000_000_000

  setup do
    agent =
      start_supervised!(
        {Agent,
         fn ->
           %{
             objects: %{},
             reads: [],
             version: 0,
             hook: nil,
             faults: %{},
             barriers: %{},
             lists: 0,
             deletes: [],
             requests: []
           }
         end}
      )

    server = start_supervised!({Bandit, plug: {CompactionStore, agent: agent}, ip: {127, 0, 0, 1}, port: 0})
    {:ok, {_, port}} = ThousandIsland.listener_info(server)

    config = %{
      bucket: "pulse",
      endpoint: "http://127.0.0.1:#{port}",
      region: "us-east-1",
      access_key_id: "pruning-#{System.unique_integer([:positive])}",
      secret_access_key: "test",
      allow_http: true,
      refresh_stale_ms: 0
    }

    Runtime.put_env(:pulse, S3, config)
    start_supervised!(ManifestSupervision)
    tenant = "pruning-#{System.unique_integer([:positive])}"

    batches = Enum.map(0..(@segments - 1), &batch/1)
    Enum.each(batches, &(:ok = S3.append(:metrics, tenant, &1)))
    :ok = Memory.append(:metrics, tenant, List.flatten(batches))

    %{agent: agent, tenant: tenant}
  end

  defp sample(i, labels),
    do: %MetricSample{timestamp_ns: @time - 60_000_000_000 + i * 1_000_000_000, value: 1.0, labels: labels}

  # Six shapes of batch, ten segments each. `up` is in every one, as every
  # scrape job produces it, so the metric name alone prunes nothing.
  defp batch(i), do: batch(rem(i, 6), i, div(i, 6))

  defp batch(0, i, _round) do
    for n <- 1..3 do
      sample(i, %{
        "__name__" => "up",
        "job" => "tuist-macos-pod-metrics",
        "env" => "canary",
        "instance" => "pod-#{i}-#{n}"
      })
    end ++
      [
        sample(i, %{
          "__name__" => "tuist_prom_ex_phoenix_endpoint_duration_ms_count",
          "job" => "tuist-macos-pod-metrics",
          "env" => "canary"
        })
      ]
  end

  defp batch(1, i, round) do
    env = if rem(round, 2) == 0, do: "canary", else: "production"
    [sample(i, %{"__name__" => "up", "job" => "tuist-macos-tart-kubelet", "env" => env, "instance" => "tart-#{i}"})]
  end

  # Mixed batch: the first record does not carry namespace or pod.
  defp batch(2, i, round) do
    namespace = if rem(round, 2) == 0, do: "tuist-canary", else: "tuist-production"

    [
      sample(i, %{"__name__" => "node_cpu_seconds_total", "job" => "node-exporter", "cpu" => "0", "mode" => "idle"}),
      sample(i, %{"__name__" => "up", "job" => "node-exporter"}),
      sample(i, %{
        "__name__" => "kube_pod_info",
        "job" => "kube-state-metrics",
        "namespace" => namespace,
        "pod" => "kura-#{i}-abc"
      })
    ]
  end

  defp batch(3, i, round) do
    [
      sample(i, %{
        "__name__" => "cnpg_pg_up",
        "job" => "cnpg",
        "cnpg_cluster" => "pg-#{rem(round, 2)}",
        "namespace" => "tuist-canary"
      }),
      sample(i, %{
        "__name__" => "kube_pod_info",
        "job" => "cnpg",
        "namespace" => "tuist-canary",
        "pod" => "cnpg-#{i}"
      }),
      sample(i, %{"__name__" => "up", "job" => "cnpg"})
    ]
  end

  # Wide OTLP-like batch: 18 high-cardinality names sort before "job".
  defp batch(4, i, _round) do
    for n <- 1..40 do
      attrs = Map.new(0..17, &{"attr_#{String.pad_leading(Integer.to_string(&1), 2, "0")}", "v#{i}-#{n}"})
      Map.merge(attrs, %{"__name__" => "otelcol_exporter_sent_spans", "job" => "otel-collector"})
    end
    |> Enum.map(&sample(i, &1))
    |> Kernel.++([sample(i, %{"__name__" => "up", "job" => "otel-collector"})])
  end

  defp batch(5, i, round) do
    queues = Enum.at([["process_xcresult"], ["process_build", "default"], ["default"]], rem(round, 3))

    Enum.map(queues, &sample(i, %{"__name__" => "oban_jobs", "job" => "tuist-server", "queue" => &1})) ++
      [sample(i, %{"__name__" => "up", "job" => "tuist-server"})]
  end

  defp segment_reads(agent),
    do: Agent.get(agent, fn state -> Enum.count(state.reads, &String.ends_with?(&1, ".parquet")) end)

  defp instant(query, tenant, adapter) do
    Runtime.put_env(:pulse, Storage, adapter: adapter)
    Evaluator.query(query, tenant, %{end_ts_ns: @time})
  end

  test "dashboard and alert selectors scan only segments their complete summaries can match", %{
    agent: agent,
    tenant: tenant
  } do
    # {query, segments read}. The comment gives the count before regex,
    # inequality and cross-record label pruning existed.
    cases = [
      # 20 before: wide segments lost `job` to their first 16 label names.
      {~S<up{job="tuist-macos-pod-metrics"}>, 10},
      # 60 before.
      {~S<up{job=~"tuist-macos-pod-metrics"}>, 10},
      {~S<up{job=~"(tuist-macos-pod-metrics)"}>, 10},
      {~S<count(up{job=~"tuist-macos-pod-metrics"} == 1)>, 10},
      {~S<up{job=~"tuist-macos-.*"}>, 20},
      {~S<up{job=~"tuist-macos-tart-kubelet|tuist-macos-pod-metrics"}>, 20},
      {~S<up{job=~"tuist-macos-tart-kubelet", instance=~".*"}>, 10},
      # Anchored: a prefix of a value is not a match.
      {~S<up{job=~"tuist-macos-pod"}>, 0},
      {~S<up{job=~"tuist-macos-.*", env!="canary"}>, 5},
      {~S<up{job=~"tuist-macos-.*", env!~"canary|staging"}>, 5},
      # Empty-label semantics: a missing env is "", which only kinds 2-5 have
      # (unknown there because no record sets env).
      {~S<up{env=""}>, 40},
      {~S<up{env=~"canary|"}>, 55},
      {~S<{__name__=~"tuist_prom_ex_phoenix.*"}>, 10},
      {~S<{__name__=~"tuist_prom_ex_phoenix_endpoint_duration_ms_count|otelcol_exporter_sent_spans"}>, 20},
      # 20 before (name only): the mixed batch's namespace and pod are now summarized.
      {~S<kube_pod_info{namespace=~"tuist-canary", pod=~"kura-(.*)-.*"}>, 5},
      {~S<cnpg_pg_up{cnpg_cluster=~".*", namespace=~"tuist-canary"}>, 10},
      {~S<oban_jobs{queue=~"process_xcresult|process_build"}>, 7},
      # Up records lack queue, so "" keeps every segment unless excluded too.
      {~S<sum by (queue) (oban_jobs{queue!~"default"})>, 10},
      {~S<sum by (queue) (oban_jobs{queue!~"default|"})>, 7},
      # Unrecognized shapes never prune.
      {~S<up{job=~"(?i)TUIST-macos-pod-metrics"}>, 60},
      {~S<up{job=~".+pod-metrics"}>, 60},
      # Only the literal prefix is known, which still excludes other jobs.
      {~S<up{job=~"tuist-macos-pod-metric[s]"}>, 10}
    ]

    for {query, expected_reads} <- cases do
      before = segment_reads(agent)
      assert {:ok, pruned} = instant(query, tenant, S3), query
      assert {query, segment_reads(agent) - before} == {query, expected_reads}
      assert {:ok, ^pruned} = instant(query, tenant, Memory)
      assert {query, pruned["data"]["result"] != []} == {query, expected_reads > 0}
    end
  end

  test "exact-name scans stay selective after the manifest name dictionary fills", %{agent: agent, tenant: tenant} do
    rare =
      for {instance, value} <- [{"left", 7.0}, {"right", 11.0}] do
        %{sample(0, %{"__name__" => "rare_metric", "instance" => instance}) | value: value}
      end

    for row <- rare, do: assert(:ok = S3.append(:metrics, tenant, [row]))
    :ok = Memory.append(:metrics, tenant, rare)

    # Distinct complete sets, not one shared set: about 450 KiB of names
    # exceed the 64 KiB dictionary while each set fits its 128-name bound.
    for batch <- 1..96 do
      rows =
        for n <- 1..32 do
          sample(0, %{"__name__" => "metric_#{batch}_#{n}_" <> String.duplicate("counter_", 20)})
        end

      assert :ok = S3.append(:metrics, tenant, rows)
      :ok = Memory.append(:metrics, tenant, rows)
    end

    Runtime.put_env(:pulse, Evaluator, max_scan_segments: 4)
    before = segment_reads(agent)
    assert {:ok, result} = instant("sum(rare_metric)", tenant, S3)
    assert segment_reads(agent) - before <= 4
    assert [%{"value" => [2000.0, "18"]}] = result["data"]["result"]
    assert {:ok, ^result} = instant("sum(rare_metric)", tenant, Memory)
    assert {:error, :query_scan_limit} = instant(~S<sum({__name__=~".+"})>, tenant, S3)
  end

  test "regex range queries over many segments stay within the scan budget", %{tenant: tenant} do
    Runtime.put_env(:pulse, Storage, adapter: S3)
    Runtime.put_env(:pulse, Evaluator, max_scan_segments: 10)
    opts = %{start_ts_ns: @time - 600_000_000_000, end_ts_ns: @time, step_ns: 15_000_000_000}
    query = ~S<count(up{job=~"tuist-macos-pod-metrics"} == 1)>
    assert {:ok, %{"data" => %{"result" => [%{"values" => values}]}}} = Evaluator.query(query, tenant, opts)
    assert values != []
    assert {:error, :query_scan_limit} = Evaluator.query(~S<count(up{job=~"tuist-.+"} == 1)>, tenant, opts)
  end
end
