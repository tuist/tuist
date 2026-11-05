# Regenerates test/fixtures/alerting/kura_recording.json: a production-shaped
# synthetic dataset for Tuist's four chained `kura:*` recording rules and the
# alert queries that read them, with reference results from Prometheus's own
# rule-group evaluation (`promtool test rules`, which evaluates each group's
# rules in order at one timestamp, appending results before the next rule).
#
#     elixir scripts/kura_recording_reference.exs /path/to/promtool
#
# The script records the promtool version it ran. Tests replay the fixture with
# the native toolchain only; promtool is needed only to regenerate it.

defmodule KuraReference do
  @fixture "test/fixtures/alerting/kura_recording.json"
  @steps 30
  @scrape 30
  # promtool starts at the Unix epoch, where timestamp() is 0 and the rules'
  # sgn(timestamp(...)) yields 0; later ticks do not depend on the epoch.
  @ticks 1..15
  @alert_times [600, 900]

  @rules [
    %{
      "record" => "kura:pod_region",
      "expr" => "max by (cluster, pod, region) (kura_node_geo_info)"
    },
    %{
      "record" => "kura:node_pool",
      "expr" =>
        "max by (cluster, node, pool) (\n  label_replace(\n    kube_node_labels{label_node_cluster_x_k8s_io_pool!=\"\"},\n    \"pool\", \"$1\", \"label_node_cluster_x_k8s_io_pool\", \"(.*)\")\n)"
    },
    %{
      "record" => "kura:pool_region",
      "expr" =>
        "max by (cluster, pool, region) (\n  (kube_pod_info{namespace=\"kura\"} * on (cluster, pod) group_left(region) sgn(topk by (cluster, pod) (1, timestamp(kura:pod_region))))\n  * on (cluster, node) group_left(pool) kura:node_pool\n)"
    },
    %{
      "record" => "kura:node_region",
      "expr" =>
        "max by (cluster, node, region) (\n  kura:node_pool * on (cluster, pool) group_left(region) sgn(topk by (cluster, pool) (1, timestamp(kura:pool_region)))\n)"
    }
  ]

  def run([promtool]) do
    {series, topology} = series()
    alerts = alerts()
    dir = Path.join(System.tmp_dir!(), "kura-reference-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    tests =
      for(t <- @ticks, rule <- @rules, do: {rule["record"], t * 60}) ++
        for t <- @alert_times, alert <- alerts, do: {alert["expr"], t}

    File.write!(Path.join(dir, "rules.yml"), rules_yaml())
    File.write!(Path.join(dir, "test.yml"), test_yaml(series, tests))
    {version, 0} = System.cmd(promtool, ["--version"])
    {output, _status} = System.cmd(promtool, ["test", "rules", "test.yml"], cd: dir, stderr_to_stdout: true)
    failures = parse(output)

    # Every recorded metric has series at most ticks; promtool also stops at
    # the first rule evaluation error, so an empty parse means it failed.
    if map_size(failures) < Enum.count(@ticks) do
      raise "promtool did not evaluate the test (inputs kept in #{dir}):\n" <> String.slice(output, 0, 4000)
    end

    File.rm_rf!(dir)
    {table, evaluations} = evaluations(tests, failures)

    fixture = %{
      "source" =>
        "Synthetic data shaped like Tuist production on 2026-11-05 (373 kura:pod_region, 69 kura:node_pool, " <>
          "11 kura:pool_region and 27 kura:node_region series), with churn: a removed pod, a region move, a new pod " <>
          "and a node moved to another pool. " <>
          "Rules and alert queries are Tuist's Grafana definitions (Atlas Grafana MCP, 2026-11-05).",
      "reference" => version |> String.split("\n") |> hd(),
      "topology" => topology,
      "scrape_interval_s" => @scrape,
      "group" => %{
        "kind" => "promql_recording_group",
        "name" => "Kura Recording",
        "cadence_ms" => 60_000,
        "enabled" => true,
        "rules" => Enum.map(@rules, &Map.put(&1, "labels", %{}))
      },
      "alerts" => alerts,
      "series" => Enum.map(series, fn {labels, values} -> %{"labels" => labels, "values" => values} end),
      "labels" => table,
      "evaluations" => evaluations
    }

    File.write!(@fixture, JSON.encode!(fixture) <> "\n")
    IO.puts("wrote #{@fixture}: #{length(series)} input series, #{length(evaluations)} evaluations")
  end

  # -- Topology ---------------------------------------------------------------

  defp clusters do
    [
      %{
        name: "tuist-production",
        kura_pools: [
          {"kura-fsn-a", "eu-central"},
          {"kura-fsn-b", "eu-central"},
          {"kura-hel-a", "eu-north"},
          {"kura-hel-b", "eu-north"},
          {"kura-ash-a", "us-east"},
          {"kura-ash-b", "us-east"},
          {"kura-sin-a", "ap-southeast"},
          {"kura-sin-b", "ap-southeast"}
        ],
        nodes_per_pool: 3,
        other_pools: [{"runners-linux", 12}, {"system", 6}, {"clickhouse", 6}],
        pods: 352
      },
      %{
        name: "tuist-canary",
        kura_pools: [{"kura-canary", "eu-central"}],
        nodes_per_pool: 1,
        other_pools: [{"runners-linux", 8}, {"system", 3}],
        pods: 10
      },
      %{
        name: "tuist-staging",
        kura_pools: [{"kura-staging-a", "eu-central"}, {"kura-staging-b", "us-east"}],
        nodes_per_pool: 1,
        other_pools: [{"runners-linux", 4}, {"system", 3}],
        pods: 11
      }
    ]
  end

  defp nodes(cluster) do
    kura =
      for {pool, region} <- cluster.kura_pools, i <- 0..(cluster.nodes_per_pool - 1),
          do: %{node: "#{cluster.name}-#{pool}-#{i}", pool: pool, region: region, kura: true}

    other =
      for {pool, count} <- cluster.other_pools, i <- 0..(count - 1),
          do: %{node: "#{cluster.name}-#{pool}-#{i}", pool: pool, region: nil, kura: false}

    kura ++ other
  end

  defp pods(cluster, nodes) do
    kura_nodes = Enum.filter(nodes, & &1.kura)

    for i <- 0..(cluster.pods - 1) do
      node = Enum.at(kura_nodes, rem(i, length(kura_nodes)))
      %{pod: "kura-#{cluster.name}-#{i}", node: node.node, region: node.region, index: i}
    end
  end

  # -- Input series -----------------------------------------------------------

  defp full, do: "1+0x#{@steps}"
  # Present before `step`, then a stale marker (the scrape target went away).
  defp until(step), do: "1+0x#{step - 1} stale"
  # Absent before `step`, present from it.
  defp from(step), do: "_x#{step} 1+0x#{@steps - step}"

  defp series do
    {series, topology} =
      Enum.reduce(clusters(), {[], %{}}, fn cluster, {acc, topology} ->
        nodes = nodes(cluster)
        pods = pods(cluster, nodes)
        {acc ++ cluster_series(cluster, nodes, pods), Map.put(topology, cluster.name, summary(cluster, nodes, pods))}
      end)

    {series, topology}
  end

  defp summary(cluster, nodes, pods),
    do: %{"nodes" => length(nodes), "kura_pools" => length(cluster.kura_pools), "kura_pods" => length(pods)}

  defp cluster_series(cluster, nodes, pods) do
    c = cluster.name
    removed = if c == "tuist-production", do: "kura-#{c}-7"
    moved = if c == "tuist-production", do: "kura-#{c}-100"
    late = if c == "tuist-canary", do: "kura-#{c}-9"
    relabeled = if c == "tuist-staging", do: "#{c}-kura-staging-b-0"
    target = Enum.find(nodes, &(&1.region == "ap-southeast"))

    geo =
      Enum.flat_map(pods, fn pod ->
        labels = %{
          "__name__" => "kura_node_geo_info",
          "cluster" => c,
          "pod" => pod.pod,
          "region" => pod.region,
          "node" => pod.node
        }

        info = %{
          "__name__" => "kube_pod_info",
          "cluster" => c,
          "namespace" => "kura",
          "pod" => pod.pod,
          "node" => pod.node
        }

        cond do
          pod.pod == removed ->
            [{labels, until(11)}, {info, until(11)}]

          pod.pod == moved ->
            new_geo = %{labels | "region" => target.region, "node" => target.node}
            new_info = %{info | "node" => target.node}
            [{labels, until(16)}, {new_geo, from(16)}, {info, until(16)}, {new_info, from(16)}]

          pod.pod == late ->
            [{labels, from(8)}, {info, from(8)}]

          true ->
            [{labels, full()}, {info, full()}]
        end
      end)

    agents =
      for node <- nodes, node.kura do
        %{
          "__name__" => "kube_pod_info",
          "cluster" => c,
          "namespace" => "kura",
          "pod" => "kura-egress-tree-agent-#{node.node}",
          "node" => node.node
        }
      end
      |> Enum.map(&{&1, full()})

    others = [
      {%{"__name__" => "kube_pod_info", "cluster" => c, "namespace" => "tuist", "pod" => "server-0", "node" => hd(nodes).node},
       full()}
    ]

    node_labels =
      Enum.flat_map(Enum.with_index(nodes), fn {node, index} ->
        labels = %{
          "__name__" => "kube_node_labels",
          "cluster" => c,
          "node" => node.node,
          "label_node_cluster_x_k8s_io_pool" => node.pool,
          "instance" => "kube-state-metrics-0"
        }

        replica = if index < 10, do: [{%{labels | "instance" => "kube-state-metrics-1"}, full()}], else: []

        if node.node == relabeled do
          [
            {labels, until(24)},
            {%{labels | "label_node_cluster_x_k8s_io_pool" => "kura-staging-c"}, from(24)}
          ]
        else
          [{labels, full()} | replica]
        end
      end)

    control_plane =
      for i <- 0..2,
          do:
            {%{
               "__name__" => "kube_node_labels",
               "cluster" => c,
               "node" => "#{c}-control-plane-#{i}",
               "instance" => "kube-state-metrics-0"
             }, full()}

    geo ++ agents ++ others ++ node_labels ++ control_plane ++ alert_inputs(c, nodes, pods, removed)
  end

  # Inputs for the alert queries: per-pod series on a sample of pods, node
  # series for every kura node and a few others, with counter resets.
  defp alert_inputs(c, nodes, pods, removed) do
    sampled = Enum.filter(pods, &(rem(&1.index, 15) == 0 or &1.pod == removed))
    kura_nodes = Enum.filter(nodes, & &1.kura) ++ Enum.take(Enum.reject(nodes, & &1.kura), 3)

    pod_series =
      Enum.flat_map(sampled, fn pod ->
        i = pod.index
        base = %{"cluster" => c, "pod" => pod.pod}
        kura = Map.merge(base, %{"namespace" => "kura", "container" => "kura"})

        sheds =
          for {kind, rate} <- [
                {"upload_memory", 3},
                {"reapi_write_decode", 1},
                {"reapi_materialization", 2},
                {"response_stream", 5}
              ] do
            values =
              if rem(i, 2) == 0,
                do: "#{i}+#{rate * rem(i, 4)}x#{@steps}",
                else: "#{i}+#{rate}x12 0+#{rate}x17"

            {Map.merge(base, %{"__name__" => "kura_capacity_sheds_total_total", "kind" => kind}), values}
          end

        streams =
          for protocol <- ["http", "grpc"], {outcome, rate} <- [{"ok", 40}, {"waited", 2}, {"degraded", rem(i, 3)}] do
            {Map.merge(base, %{
               "__name__" => "kura_response_stream_admissions_total_total",
               "protocol" => protocol,
               "outcome" => outcome
             }), "0+#{rate}x#{@steps}"}
          end

        buckets =
          for {le, rate} <- [{"0.1", 20}, {"0.5", 35}, {"1", 38}, {"+Inf", 40}] do
            {Map.merge(base, %{"__name__" => "kura_public_request_latency_seconds_bucket", "le" => le}),
             "0+#{rate + rem(i, 5)}x#{@steps}"}
          end

        requests =
          for {resource, value} <- [
                {"memory", 4_294_967_296},
                {"tuist_dev_memory_ceiling_mib", 4096},
                {"ephemeral_storage", 53_687_091_200},
                {"tuist_dev_egress_mbps", 25}
              ] do
            {Map.merge(kura, %{
               "__name__" => "kube_pod_container_resource_requests",
               "resource" => resource,
               "node" => pod.node,
               "unit" => "byte"
             }), "#{value}+0x#{@steps}"}
          end

        [
          {Map.put(base, "__name__", "kura_memory_pressure_state"), "#{rem(i, 3)}+0x15 #{rem(i + 1, 3)}+0x14"},
          {Map.put(base, "__name__", "kura_container_memory_pressure_bytes"),
           "#{3_000_000_000 + i * 10_000_000}+#{1_000_000 * rem(i, 7)}x#{@steps}"},
          {Map.put(base, "__name__", "kura_container_memory_oom_kill_events"), "0+#{rem(i, 2)}x#{@steps}"},
          {Map.merge(kura, %{"__name__" => "kube_pod_container_status_restarts_total"}),
           "#{rem(i, 4)}+#{rem(i, 2)}x#{@steps}"},
          {Map.merge(kura, %{"__name__" => "kube_pod_container_status_last_terminated_reason", "reason" => "OOMKilled"}),
           "#{rem(i, 2)}+0x#{@steps}"},
          {Map.put(base, "__name__", "kura_public_request_latency_seconds_count"), "0+#{40 + rem(i, 5)}x#{@steps}"}
        ] ++ sheds ++ streams ++ buckets ++ requests
      end)

    node_series =
      Enum.flat_map(Enum.with_index(kura_nodes), fn {node, i} ->
        base = %{"cluster" => c, "node" => node.node}
        instance = %{"cluster" => c, "instance" => node.node}
        agent = "kura-egress-tree-agent-#{node.node}"
        agent_base = %{"cluster" => c, "pod" => agent}

        [
          {Map.merge(base, %{"__name__" => "kube_node_status_capacity", "resource" => "tuist_dev_memory_ceiling_mib"}),
           "#{65_536 + 4096 * i}+0x#{@steps}"},
          {Map.merge(base, %{"__name__" => "kube_node_status_capacity", "resource" => "tuist_dev_egress_mbps"}),
           "#{1000 + 50 * rem(i, 3)}+0x#{@steps}"},
          {Map.merge(base, %{"__name__" => "kube_node_status_allocatable", "resource" => "memory"}),
           "#{137_438_953_472 + 1_073_741_824 * i}+0x#{@steps}"},
          {Map.merge(base, %{"__name__" => "kube_node_status_allocatable", "resource" => "ephemeral_storage"}),
           "#{1_099_511_627_776 + 10_737_418_240 * i}+0x#{@steps}"},
          {Map.put(instance, "__name__", "node_memory_MemTotal_bytes"), "#{137_438_953_472 + 1_073_741_824 * i}+0x#{@steps}"},
          {Map.put(instance, "__name__", "node_memory_MemAvailable_bytes"),
           "#{40_000_000_000 + 1_000_000_000 * i}-#{100_000_000 * rem(i, 3)}x#{@steps}"},
          {Map.merge(instance, %{"__name__" => "node_network_transmit_bytes_total", "device" => "eth0"}),
           "0+#{3_000_000_000 + 250_000_000 * i}x#{@steps}"},
          {Map.merge(instance, %{"__name__" => "node_network_transmit_bytes_total", "device" => "lo"}),
           "0+900000000x#{@steps}"},
          {Map.put(instance, "__name__", "node_softnet_dropped_total"), "0+#{rem(i, 2)}x#{@steps}"},
          {Map.merge(agent_base, %{"__name__" => "up", "job" => "egress-tree-agent"}),
           if(rem(i, 5) == 4, do: "0+0x#{@steps}", else: full())},
          {Map.put(agent_base, "__name__", "kura_egress_tree_direct_packets"), "0+#{rem(i, 3)}x#{@steps}"},
          {Map.put(agent_base, "__name__", "kura_egress_tree_return_dropped_packets"), "0+0x#{@steps}"},
          {Map.put(agent_base, "__name__", "kura_egress_tree_return_attach_failures_total"), "0+#{div(rem(i, 7), 6)}x#{@steps}"},
          {Map.put(agent_base, "__name__", "kura_egress_tree_reconcile_errors_total"), "0+0x#{@steps}"},
          {Map.put(agent_base, "__name__", "kura_egress_tree_sibling_overflow_total"), "0+0x#{@steps}"},
          {Map.put(agent_base, "__name__", "kura_egress_tree_link_reattach_total"), "0+#{rem(i, 2)}x#{@steps}"},
          {Map.put(agent_base, "__name__", "kura_egress_tree_skipped_pods"), "#{div(rem(i, 9), 8)}+0x#{@steps}"},
          {Map.put(agent_base, "__name__", "kura_egress_tree_node_budget_mbps"),
           "#{1000 + 50 * rem(i + div(i, 4), 3)}+0x#{@steps}"},
          {Map.merge(agent_base, %{"__name__" => "kura_egress_tree_class_sent_bytes", "account" => "acct-#{rem(i, 4)}"}),
           "0+#{100_000_000 + 7_000_000 * i}x#{@steps}"},
          {Map.merge(agent_base, %{
             "__name__" => "kura_egress_tree_class_ceil_bytes_per_second",
             "account" => "acct-#{rem(i, 4)}"
           }), "#{3_500_000 + 100_000 * i}+0x#{@steps}"}
        ]
      end)

    pod_series ++ node_series
  end

  # The 16 distinct queries of the 17 Grafana alert rules that read kura:*.
  defp alerts do
    "test/fixtures/alerting/kura_alerts.json" |> File.read!() |> JSON.decode!()
  end

  # -- promtool ---------------------------------------------------------------

  defp rules_yaml do
    rules =
      Enum.map_join(@rules, "", fn rule ->
        "      - record: #{rule["record"]}\n        expr: #{JSON.encode!(rule["expr"])}\n"
      end)

    "groups:\n  - name: Kura Recording\n    interval: 1m\n    rules:\n" <> rules
  end

  defp test_yaml(series, tests) do
    inputs =
      Enum.map_join(series, "", fn {labels, values} ->
        "      - series: #{JSON.encode!(selector(labels))}\n        values: #{JSON.encode!(values)}\n"
      end)

    checks =
      Enum.map_join(tests, "", fn {expr, t} ->
        "      - expr: #{JSON.encode!(expr)}\n        eval_time: #{t}s\n        exp_samples: []\n"
      end)

    "rule_files: [rules.yml]\nevaluation_interval: 1m\ntests:\n  - interval: #{@scrape}s\n    input_series:\n" <>
      inputs <> "    promql_expr_test:\n" <> checks
  end

  defp selector(labels) do
    {name, rest} = Map.pop(labels, "__name__")
    body = rest |> Enum.sort() |> Enum.map_join(", ", fn {k, v} -> "#{k}=#{JSON.encode!(v)}" end)
    "#{name}{#{body}}"
  end

  # promtool prints every non-empty result as a failure against `exp: nil`.
  defp parse(output) do
    lines = String.split(output, "\n")

    lines
    |> Enum.with_index()
    |> Enum.filter(fn {line, _} -> String.starts_with?(String.trim_leading(line), "expr: ") end)
    |> Map.new(fn {line, index} ->
      [_, expr, time] = Regex.run(~r/^\s*expr: (".*"), time: ([^,]+),\s*$/, line)
      got = Enum.at(lines, index + 2) |> String.trim_leading()
      "got: " <> samples = got
      {{JSON.decode!(expr), duration(time)}, samples(samples)}
    end)
  end

  defp duration(text) do
    Regex.scan(~r/(\d+)(h|m|s)/, text)
    |> Enum.reduce(0, fn [_, n, unit], acc ->
      acc + String.to_integer(n) * %{"h" => 3600, "m" => 60, "s" => 1}[unit]
    end)
  end

  defp samples("nil"), do: []
  defp samples(text), do: samples(text, [])

  defp samples("", acc), do: Enum.reverse(acc)
  defp samples(", " <> rest, acc), do: samples(rest, acc)

  defp samples("{" <> rest, acc) do
    {labels, rest} = labels(rest, %{})
    " " <> rest = rest
    [value | _] = String.split(rest, ", {", parts: 2)
    rest = String.replace_prefix(rest, value, "")
    samples(rest, [{labels, value} | acc])
  end

  defp labels("}" <> rest, acc), do: {acc, rest}
  defp labels(", " <> rest, acc), do: labels(rest, acc)

  defp labels(text, acc) do
    [name, rest] = String.split(text, "=", parts: 2)
    {value, rest} = quoted(rest)
    labels(rest, Map.put(acc, name, value))
  end

  defp quoted("\"" <> rest), do: quoted(rest, "")
  defp quoted("\\\"" <> rest, acc), do: quoted(rest, acc <> "\"")
  defp quoted("\\\\" <> rest, acc), do: quoted(rest, acc <> "\\")
  defp quoted("\"" <> rest, acc), do: {acc, rest}
  defp quoted(<<c::utf8, rest::binary>>, acc), do: quoted(rest, acc <> <<c::utf8>>)

  defp evaluations(tests, failures) do
    results = Enum.map(tests, &{&1, Map.get(failures, &1, [])})
    table = results |> Enum.flat_map(fn {_, samples} -> Enum.map(samples, &elem(&1, 0)) end) |> Enum.uniq()
    ids = table |> Enum.with_index() |> Map.new()

    evaluations =
      Enum.map(results, fn {{expr, t}, samples} ->
        %{"expr" => expr, "time_s" => t, "result" => Enum.map(samples, fn {labels, value} -> [ids[labels], value] end)}
      end)

    {table, evaluations}
  end
end

KuraReference.run(System.argv())
