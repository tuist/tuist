defmodule Pulse.Test.TuistMetricHistory do
  @moduledoc """
  Remote-write history shaped like Tuist's canary or production metrics, for
  `test/pulse/promql/tuist_history_bench_test.exs`.

  Series carry Tuist's metric names: every metric the Grafana corpus
  (`test/fixtures/grafana/tuist-corpus.json`) selects, with the labels its
  queries group and join by (`Pulse.Test.GrafanaCorpus.metric_series/1`),
  replicated over more pods, plus explicit families with realistic
  cardinality for the dashboard panels that fail on canary (Phoenix and Oban
  histograms, node_exporter, `up`, repo pools, Finch, kura), and
  node_exporter, kube-state-metrics and cAdvisor series to fill the volume.

  Every series belongs to a scrape target with its own phase. A batch holds
  the samples whose scrape time falls in its window, as Pulse's ingest
  coalescing (`PULSE_INGEST_FLUSH_INTERVAL_MS=2000`) writes one segment per
  window: `:canary` is 150,000 series scraped every 60 s (5,000 samples per
  2 s batch, about 110 KB segments, as on canary), `:production` 400,000
  series every 30 s (26,667 per batch, the volume
  `scripts/production_load.exs` drives). Values are deterministic, so
  two histories built from the same arguments are identical.
  """

  alias Pulse.Record.MetricSample
  alias Pulse.Test.GrafanaCorpus

  @batch_ms 2_000

  # Panel metrics with explicit families; the corpus-derived series for these
  # names are replaced.
  @explicit ~w(
    tuist_prom_ex_phoenix_http_request_duration_milliseconds_bucket
    tuist_prom_ex_phoenix_http_request_duration_milliseconds_sum
    tuist_prom_ex_phoenix_http_request_duration_milliseconds_count
    tuist_oban_job_processing_duration_milliseconds_bucket
    tuist_oban_job_processing_duration_milliseconds_sum
    tuist_oban_job_processing_duration_milliseconds_count
    node_cpu_seconds_total up tuist_http_request_count
    tuist_repo_pool_checkout_queue_length tuist_repo_pool_checkout_queue_starved_samples
    tuist_repo_pool_checkout_queue_total_samples tuist_repo_query_count tuist_runners_claims_count
    kura_file_descriptor_wait_seconds_count kura_file_descriptor_wait_seconds_sum
    tuist_kura_rollout_active tuist_kura_rollout_wave tuist_kura_rollout_paused
  )

  @doc """
  Scrape interval, series count and family sizes of a volume. Canary: a 60 s
  scrape (Alloy's default, and what canary's `up{job="kura"}` hitting 55%
  of batches implies for its targets), histogram families just under 100,000
  samples an hour, as canary's panels exceed the query heap before the
  default sample budget. Production: `scripts/production_load.exs`.
  """
  def shape(:canary),
    do: %{
      scrape_ms: 60_000,
      series: 150_000,
      server_pods: 3,
      histogram_pods: 2,
      kura_pods: 24,
      nodes: 12,
      routes: 72,
      workers: 45,
      runner_pods: 1,
      replicas: 8
    }

  def shape(:production),
    do: %{
      scrape_ms: 30_000,
      series: 400_000,
      server_pods: 24,
      histogram_pods: 12,
      kura_pods: 64,
      nodes: 48,
      routes: 120,
      workers: 45,
      runner_pods: 4,
      replicas: 16
    }

  def batch_ms, do: @batch_ms

  @doc """
  Corpus queries with the substitution the canary alert run used:
  production cluster and env values become canary's.
  """
  def canary_expr(expr) do
    expr
    |> String.replace("tuist-production", "tuist-canary")
    |> String.replace(~r/env(=~?)"(production|prod)"/, ~s|env\\1"canary"|)
  end

  @doc """
  `{targets, count}`: scrape targets as `{phase_ms, series}` sorted by phase,
  each series `{labels, kind, seed}`.
  """
  def targets(volume, requests) do
    %{series: total, scrape_ms: scrape} = shape = shape(volume)
    explicit = explicit_series(shape)
    corpus = corpus_series(requests, shape.replicas)
    used = length(explicit) + length(corpus)
    filler = filler_series(max(total - used, 0), shape.nodes)

    targets =
      (explicit ++ corpus ++ filler)
      |> Enum.group_by(&target_of/1)
      |> Enum.map(fn {target, series} ->
        {rem(:erlang.phash2(target), scrape),
         Enum.map(series, fn {labels, kind} ->
           labels = Map.delete(labels, "__target__")
           {labels, kind, seed(labels)}
         end)}
      end)
      |> Enum.sort()

    {targets, Enum.sum_by(targets, fn {_, series} -> length(series) end)}
  end

  # A histogram bucket's seed is its family's, so buckets stay cumulative.
  defp seed(labels), do: :erlang.phash2(Map.delete(labels, "le"))

  defp target_of({labels, _kind}), do: labels["__target__"] || {labels["instance"], labels["pod"], labels["job"]}

  @doc """
  Samples of the batch covering `[from_ms, from_ms + #{@batch_ms})`, for
  scrapes numbered from `origin_ms`.
  """
  def batch(targets, volume, origin_ms, from_ms) do
    scrape = shape(volume).scrape_ms
    to_ms = from_ms + @batch_ms

    for {phase, series} <- targets,
        at = first_scrape(origin_ms + phase, scrape, from_ms),
        at < to_ms,
        n = div(at - origin_ms - phase, scrape),
        {labels, kind, seed} <- series do
      %MetricSample{timestamp_ns: at * 1_000_000, value: value(kind, seed, n, at), labels: labels}
    end
  end

  # The first scrape of a target (times `start + k * scrape`) at or after `from`.
  defp first_scrape(start, _scrape, from) when from <= start, do: start
  defp first_scrape(start, scrape, from), do: start + div(from - start + scrape - 1, scrape) * scrape

  # -- values ---------------------------------------------------------------

  defp value(:info, _seed, _n, _at), do: 1.0
  defp value(:flag, seed, n, _at), do: if(rem(seed + div(n, 40), 97) == 0, do: 0.0, else: 1.0)
  defp value(:timestamp, seed, _n, at), do: (div(at, 1000) - rem(seed, 1800)) * 1.0
  defp value(:gauge, seed, n, _at), do: rem(:erlang.phash2({seed, div(n, 4)}), 4000) / 4
  defp value(:counter, seed, n, _at), do: counter(seed, n, 1.0)
  defp value({:bucket, fraction}, seed, n, _at), do: counter(seed, n, fraction)

  # Monotonic, increments of 0..(rate - 1) per scrape, resetting once a day
  # for a tenth of the series.
  defp counter(seed, n, fraction) do
    rate = rem(seed, 40) + 1
    n = if rem(seed, 10) == 3, do: rem(n + rem(seed, 5760), 5760), else: n
    Float.floor(n * rate * fraction + rem(seed, 500) * fraction)
  end

  defp bucket_fraction("+Inf"), do: 1.0

  defp bucket_fraction(le) do
    {value, _} = Float.parse(le)
    min(1.0, 0.2 + :math.log10(1 + max(value, 0.0)) / 6)
  end

  defp kind(name) do
    cond do
      String.ends_with?(name, "_bucket") -> :counter
      String.ends_with?(name, ["_total", "_count", "_sum", "_samples"]) -> :counter
      String.ends_with?(name, "_info") or name == "kube_pod_info" -> :info
      String.contains?(name, ["timestamp", "_time_seconds", "_created", "mtime"]) -> :timestamp
      name == "up" or String.ends_with?(name, ~w(_up _ready _healthy _success _reachable _active _paused)) -> :flag
      true -> :gauge
    end
  end

  defp series(labels) do
    name = labels["__name__"]

    kind =
      if String.ends_with?(name, "_bucket"),
        do: {:bucket, bucket_fraction(labels["le"])},
        else: kind(name)

    {labels, kind}
  end

  # -- explicit panel families ------------------------------------------------

  @phoenix_buckets ~w(10 100 500 1000 5000 10000 30000 +Inf)
  @oban_buckets ~w(10 100 500 1000 5000 10000 60000 +Inf)
  @methods ~w(GET POST PUT DELETE)

  defp explicit_series(s) do
    c = %{
      s: s,
      canary: %{"cluster" => "tuist-canary", "env" => "canary"},
      server_pods: for(p <- 1..s.server_pods, do: "tuist-canary-server-#{p}"),
      kura_pods: for(p <- 1..s.kura_pods, do: "kura-canary-#{rem(p, 2)}-#{kura_region(p)}-#{p}"),
      nodes: for(n <- 1..s.nodes, do: "node-#{n}")
    }

    Enum.map(histogram_series(c) ++ node_series(c) ++ app_series(c) ++ kura_series(c) ++ up_series(c), &series/1)
  end

  defp kura_region(p) when rem(p, 3) == 0, do: "fr-par"
  defp kura_region(_), do: "nl-ams"

  defp histogram_series(%{s: s, canary: canary, server_pods: server_pods}) do
    # Sized so a 1-hour panel over all routes selects fewer than canary's
    # default 100,000 samples, as on canary, where these panels exceed the
    # query heap rather than the sample budget.
    phoenix =
      for pod <- Enum.take(server_pods, s.histogram_pods),
          route <- 1..s.routes,
          status <- if(rem(route, 4) == 0, do: ~w(200 404), else: ~w(200)),
          suffix <- ["bucket", "sum", "count"],
          le <- if(suffix == "bucket", do: @phoenix_buckets, else: [nil]) do
        Map.merge(canary, %{
          "__name__" => "tuist_prom_ex_phoenix_http_request_duration_milliseconds_" <> suffix,
          "instance" => pod,
          "pod" => pod,
          "job" => "tuist",
          "host" => "canary.tuist.dev",
          "method" => Enum.at(@methods, rem(route, 4)),
          "path" => "/api/projects/:account/:project/r#{route}",
          "status" => status
        })
        |> put_le(le)
      end

    oban =
      for pod <- Enum.take(server_pods, s.histogram_pods),
          worker <- 1..s.workers,
          state <- ~w(success failure),
          suffix <- ["bucket", "sum", "count"],
          le <- if(suffix == "bucket", do: @oban_buckets, else: [nil]) do
        Map.merge(canary, %{
          "__name__" => "tuist_oban_job_processing_duration_milliseconds_" <> suffix,
          "instance" => pod,
          "pod" => pod,
          "job" => "tuist",
          "name" => "Oban",
          "queue" => "q#{rem(worker, 6)}",
          "worker" => "Tuist.Workers.Worker#{worker}",
          "state" => state
        })
        |> put_le(le)
      end

    phoenix ++ oban
  end

  defp node_series(%{nodes: nodes}) do
    node_cpu =
      for node <- nodes, cpu <- 0..15, mode <- ~w(idle user system iowait irq softirq steal nice) do
        %{
          "__name__" => "node_cpu_seconds_total",
          "cluster" => "tuist-canary",
          "instance" => node,
          "node" => node,
          "job" => "node-exporter",
          "cpu" => Integer.to_string(cpu),
          "mode" => mode
        }
      end

    node_cpu
  end

  defp kura_series(%{canary: canary, server_pods: server_pods, kura_pods: kura_pods}) do
    kura =
      for pod <- kura_pods,
          result <- ~w(ok timeout cancelled),
          name <- ~w(count sum),
          do: %{
            "__name__" => "kura_file_descriptor_wait_seconds_" <> name,
            "cluster" => "tuist-canary",
            "namespace" => "kura",
            "job" => "kura",
            "pod" => pod,
            "instance" => pod,
            "result" => result
          }

    rollout =
      for name <- ~w(active wave paused),
          mode <- ~w(canary steady),
          do:
            Map.merge(canary, %{
              "__name__" => "tuist_kura_rollout_" <> name,
              "image_tag" => "1.4.#{if mode == "canary", do: 2, else: 1}",
              "mode" => mode,
              "job" => "tuist",
              "instance" => hd(server_pods),
              "pod" => hd(server_pods)
            })

    kura ++ rollout
  end

  defp app_series(%{s: s, canary: canary, server_pods: server_pods}) do
    repo =
      for pod <- server_pods,
          workload <- ~w(server worker processor),
          repo <- ~w(Tuist.Repo Tuist.IngestRepo Tuist.ClickHouseRepo Tuist.ReadRepo),
          name <- ~w(length starved_samples total_samples),
          do:
            Map.merge(canary, %{
              "__name__" => "tuist_repo_pool_checkout_queue_" <> name,
              "pod" => pod,
              "instance" => pod,
              "job" => "tuist",
              "workload" => workload,
              "repo" => repo
            })

    queries =
      for pod <- server_pods,
          workload <- ~w(server worker processor),
          repo <- ~w(Tuist.Repo Tuist.IngestRepo Tuist.ClickHouseRepo Tuist.ReadRepo),
          result <- ~w(ok error timeout),
          do:
            Map.merge(canary, %{
              "__name__" => "tuist_repo_query_count",
              "pod" => pod,
              "instance" => pod,
              "job" => "tuist",
              "workload" => workload,
              "repo" => repo,
              "result" => result
            })

    runners =
      for pod <- Enum.take(server_pods, s.runner_pods),
          state <- ~w(pending claimed running finished failed),
          fleet <- ~w(macos-m4 macos-m2 linux-x64 linux-arm),
          do:
            Map.merge(canary, %{
              "__name__" => "tuist_runners_claims_count",
              "pod" => pod,
              "instance" => pod,
              "job" => "tuist",
              "lifecycle_state" => state,
              "fleet" => fleet
            })

    finch =
      for pod <- server_pods,
          host <-
            ~w(api.github.com s3.tigris.dev clickhouse.internal hooks.slack.com api.stripe.com oauth2.googleapis.com),
          method <- ~w(GET POST PUT),
          status <- ~w(200 201 404 500),
          do:
            Map.merge(canary, %{
              "__name__" => "tuist_http_request_count",
              "pod" => pod,
              "instance" => pod,
              "job" => "tuist",
              "request_host" => host,
              "request_method" => method,
              "response_status" => status
            })

    repo ++ queries ++ runners ++ finch
  end

  defp up_series(%{server_pods: server_pods, kura_pods: kura_pods, nodes: nodes}) do
    # One `up` per scrape target of the explicit and filler families.
    targets =
      for(pod <- kura_pods, do: {"kura", pod, "kura"}) ++
        for(pod <- server_pods, do: {"tuist", pod, "tuist-canary"}) ++
        for(node <- nodes, job <- ~w(node-exporter kubelet cadvisor), do: {job, node, "kube-system"})

    for {job, pod, namespace} <- targets,
        do: %{
          "__name__" => "up",
          "cluster" => "tuist-canary",
          "env" => "canary",
          "namespace" => namespace,
          "job" => job,
          "instance" => pod,
          "pod" => pod
        }
  end

  defp put_le(labels, nil), do: labels
  defp put_le(labels, le), do: Map.put(labels, "le", le)

  # -- corpus-derived series ----------------------------------------------------

  # Each corpus series once as the corpus derives it, and `replicas` more
  # copies on other pods and instances, which keep matching regex matchers.
  defp corpus_series(requests, replicas) do
    requests
    |> GrafanaCorpus.metric_series()
    |> Enum.map(&elem(&1, 0))
    |> Enum.reject(&(&1["__name__"] in @explicit))
    |> Enum.flat_map(fn labels ->
      [labels | for(r <- 1..replicas//1, do: replica(labels, r))]
    end)
    |> Enum.uniq()
    |> Enum.map(&series/1)
  end

  defp replica(labels, r) do
    Enum.reduce(~w(pod instance node), labels, fn key, acc ->
      case acc do
        %{^key => value} -> Map.put(acc, key, "#{value}-r#{r}")
        _ -> acc
      end
    end)
  end

  # -- filler -----------------------------------------------------------------

  @node_metrics ~w(
    node_memory_MemAvailable_bytes node_memory_MemFree_bytes node_memory_Cached_bytes node_memory_Buffers_bytes
    node_memory_Active_bytes node_memory_Inactive_bytes node_memory_Dirty_bytes node_memory_Slab_bytes
    node_load1 node_load5 node_load15 node_procs_running node_procs_blocked node_context_switches_total
    node_intr_total node_forks_total node_boot_time_seconds node_time_seconds node_entropy_available_bits
    node_filefd_allocated node_filefd_maximum node_sockstat_TCP_inuse node_sockstat_TCP_tw node_sockstat_UDP_inuse
    node_netstat_Tcp_ActiveOpens node_netstat_Tcp_PassiveOpens node_netstat_Tcp_RetransSegs node_netstat_Tcp_InSegs
    node_netstat_Tcp_OutSegs node_netstat_Udp_InDatagrams node_netstat_Udp_OutDatagrams node_vmstat_pgfault
    node_vmstat_pgmajfault node_vmstat_pswpin node_vmstat_pswpout node_vmstat_oom_kill node_pressure_cpu_waiting_seconds_total
    node_pressure_memory_waiting_seconds_total node_pressure_io_waiting_seconds_total node_schedstat_running_seconds_total
    node_schedstat_waiting_seconds_total node_schedstat_timeslices_total node_softnet_processed_total node_softnet_dropped_total
    node_cpu_guest_seconds_total node_cpu_scaling_frequency_hertz node_thermal_zone_temp node_hwmon_temp_celsius
  )
  @node_device_metrics ~w(
    node_network_receive_packets_total node_network_transmit_packets_total node_network_receive_errs_total
    node_network_transmit_errs_total node_network_receive_drop_total node_network_transmit_drop_total node_network_up
    node_network_mtu_bytes node_network_speed_bytes node_network_carrier node_disk_read_bytes_total
    node_disk_written_bytes_total node_disk_reads_completed_total node_disk_writes_completed_total node_disk_io_time_seconds_total
    node_disk_read_time_seconds_total node_disk_write_time_seconds_total node_disk_io_now node_filesystem_files
    node_filesystem_files_free node_filesystem_free_bytes node_filesystem_readonly node_filesystem_device_error
  )
  @kube_metrics ~w(
    kube_pod_status_phase kube_pod_status_ready kube_pod_container_status_running kube_pod_container_status_waiting
    kube_pod_container_status_terminated kube_pod_container_resource_requests kube_pod_container_resource_limits
    kube_pod_owner kube_pod_labels kube_pod_created kube_pod_start_time kube_pod_status_scheduled kube_pod_container_info
    kube_pod_container_status_last_terminated_reason kube_pod_container_status_ready kube_pod_annotations
  )
  @container_metrics ~w(
    container_cpu_usage_seconds_total container_cpu_cfs_periods_total container_cpu_cfs_throttled_periods_total
    container_memory_working_set_bytes container_memory_rss container_memory_cache container_memory_usage_bytes
    container_memory_swap container_network_receive_bytes_total container_network_transmit_bytes_total
    container_fs_reads_bytes_total container_fs_writes_bytes_total container_file_descriptors container_threads
    container_last_seen container_spec_memory_limit_bytes container_spec_cpu_shares container_oom_events_total
  )

  # node_exporter per node (one series per metric, per device for device
  # metrics), then kube-state-metrics (16 shards) and cAdvisor (per node)
  # per pod until `count` series exist.
  defp filler_series(count, nodes) do
    nodes = for n <- 1..nodes, do: "node-#{n}"

    node =
      for node <- nodes,
          {name, devices} <- Enum.map(@node_metrics, &{&1, [nil]}) ++ Enum.map(@node_device_metrics, &{&1, devices()}),
          device <- devices do
        labels = %{
          "__name__" => name,
          "cluster" => "tuist-canary",
          "instance" => node,
          "node" => node,
          "job" => "node-exporter"
        }

        if device, do: Map.put(labels, "device", device), else: labels
      end

    pods =
      Stream.iterate(0, &(&1 + 1))
      |> Stream.flat_map(fn p ->
        pod = "workload-#{rem(p, 97)}-#{p}"
        namespace = Enum.at(~w(tuist-canary kura kube-system observability cnpg-system ingress-nginx), rem(p, 6))
        node = Enum.at(nodes, rem(p, length(nodes)))

        kube =
          for name <- @kube_metrics,
              do: %{
                "__name__" => name,
                "cluster" => "tuist-canary",
                "namespace" => namespace,
                "pod" => pod,
                "container" => "main",
                "job" => "kube-state-metrics",
                "instance" => "kube-state-metrics:8080",
                "__target__" => {"kube-state-metrics", rem(p, 16)}
              }

        cadvisor =
          for name <- @container_metrics,
              do: %{
                "__name__" => name,
                "cluster" => "tuist-canary",
                "namespace" => namespace,
                "pod" => pod,
                "container" => "main",
                "job" => "cadvisor",
                "instance" => node,
                "node" => node,
                "__target__" => {"cadvisor", node}
              }

        kube ++ cadvisor
      end)

    (node ++ Enum.take(pods, max(count - length(node), 0)))
    |> Enum.take(count)
    |> Enum.map(&series/1)
  end

  defp devices, do: ~w(eth0 eth1 nvme0n1 nvme1n1 lo cilium_host)
end
