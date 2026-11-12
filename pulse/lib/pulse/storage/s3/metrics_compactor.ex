defmodule Pulse.Storage.S3.MetricsCompactor do
  @moduledoc """
  Bounded metrics compaction and restart-safe cleanup through the shared signal
  compactor. Flat manifests preserve retirement tombstones; retention-managed
  manifests fence publication and reclaim metadata through immutable pages.
  """
  alias Pulse.Storage.S3.JournalManifest
  alias Pulse.Storage.S3.Retention
  alias Pulse.Storage.S3.SignalCompactor

  def compact(tenant, config, opts \\ []) do
    if config[:maintenance_operation] == :metric_compact and Map.get(config, :metric_finalize_enabled, true) do
      # Grouping/finalization already rewrite these rows. A small raw merge
      # racing their much larger native build retires some of its sources,
      # making publication impossible even after replanning fresh pages.
      # Keep the legacy merger for format 3, which tiers do not support.
      with {:ok, root, _etag} <- Retention.load(tenant, "metrics", config) do
        compact_root(root, tenant, config, opts)
      end
    else
      merge(tenant, config, opts)
    end
  end

  defp compact_root(%{version: 3}, tenant, config, opts), do: merge(tenant, config, opts)

  defp compact_root(root, tenant, config, _opts) do
    with :ok <- advance_cursor(root, tenant, config),
         do: {:ok, %{segments_before: length(root.segments), merged: 0}}
  end

  # Grouping/finalization inspect this same bounded historical window. Keep
  # rotating it even though they, rather than the legacy merger, rewrite rows.
  defp advance_cursor(%{version: 4} = root, tenant, config) do
    with {:ok, candidates} <- JournalManifest.candidates(root, tenant, "metrics", config),
         do:
           SignalCompactor.advance_empty_cursor(root, candidates, tenant, Map.put(config, :compaction_signal, :metrics))
  end

  defp advance_cursor(_root, _tenant, _config), do: :ok

  defp merge(tenant, config, opts),
    do: SignalCompactor.compact(tenant, Map.put(config, :compaction_signal, :metrics), opts)

  def cleanup(tenant, config, opts \\ []),
    do: SignalCompactor.cleanup(tenant, Map.put(config, :compaction_signal, :metrics), opts)

  def select(manifest, opts \\ []), do: SignalCompactor.select(manifest, opts)
end
