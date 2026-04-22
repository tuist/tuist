defmodule Tuist.Metrics do
  @moduledoc """
  Per-account telemetry aggregation for the Prometheus-compatible `/metrics`
  scrape endpoint.

  Each node maintains a local ETS table of counters and histogram data,
  indexed by `{account_id, metric_name, labels}`. When an account is scraped
  the receiving node fans out to every peer in the cluster and merges the
  snapshots before rendering. This presents a consistent view across rolling
  deploys: even while one node drains, its counters are still visible until it
  stops responding to RPCs.

  The aggregator resets on deployment. That is an expected property: Prometheus
  query functions (`rate/1`, `increase/1`) are reset-aware, and ClickHouse
  remains the authoritative store for historical analytics.
  """

  alias Tuist.Metrics.Aggregator
  alias Tuist.Metrics.Schema

  @rpc_timeout to_timeout(second: 3)

  @doc """
  Returns the metric definitions exposed through the scrape endpoint.
  """
  defdelegate metric_definitions(), to: Schema, as: :definitions

  @doc """
  Returns a merged snapshot of an account's metrics across every node in the
  cluster. The local node is always included; remote RPC failures are logged
  and skipped so a partially reachable cluster still produces output.
  """
  def snapshot(account_id) do
    local = Aggregator.snapshot(account_id)

    Node.list()
    |> Enum.map(fn node ->
      {node, :rpc.call(node, Aggregator, :snapshot, [account_id], @rpc_timeout)}
    end)
    |> Enum.reduce(local, fn
      {_node, {:badrpc, _reason}}, acc -> acc
      {_node, remote}, acc when is_list(remote) -> merge(acc, remote)
      _, acc -> acc
    end)
  end

  @doc """
  Increments a counter by one for `account_id`. Labels may be provided as a
  map (normalised against the schema) or as the canonical tuple.
  """
  def increment_counter(account_id, metric, labels, count \\ 1) do
    Aggregator.increment_counter(account_id, metric, normalise_labels(metric, labels), count)
  end

  @doc """
  Observes a duration (in seconds) against a histogram metric. Labels may be
  provided as a map (normalised against the schema) or as the canonical tuple.
  """
  def observe_histogram(account_id, metric, labels, value_seconds) do
    Aggregator.observe_histogram(
      account_id,
      metric,
      normalise_labels(metric, labels),
      value_seconds
    )
  end

  defp normalise_labels(_metric, labels) when is_tuple(labels), do: labels

  defp normalise_labels(metric, labels) when is_map(labels), do: Schema.label_tuple!(metric, labels)

  @doc false
  def merge(snapshots_a, snapshots_b) do
    index = Map.new(snapshots_a, &{{&1.metric, &1.labels}, &1})

    snapshots_b
    |> Enum.reduce(index, fn %{metric: m, labels: l} = entry, acc ->
      Map.update(acc, {m, l}, entry, &merge_entry(&1, entry))
    end)
    |> Map.values()
  end

  defp merge_entry(%{type: :counter, value: v1} = a, %{type: :counter, value: v2}), do: %{a | value: v1 + v2}

  defp merge_entry(%{type: :histogram} = a, %{type: :histogram} = b) do
    # Merge by bucket bound rather than by list position so two snapshots
    # with different bucket layouts (e.g. mid-deploy schema drift) combine
    # losslessly rather than silently truncating to the shorter list.
    merged_buckets =
      (a.buckets ++ b.buckets)
      |> Enum.reduce(%{}, fn {bound, count}, acc ->
        Map.update(acc, bound, count, &(&1 + count))
      end)
      |> Enum.sort_by(&elem(&1, 0))

    %{a | count: a.count + b.count, sum: a.sum + b.sum, buckets: merged_buckets}
  end
end
