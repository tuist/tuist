defmodule Pulse.Storage.S3.MetricsCompactor do
  @moduledoc """
  Bounded metrics compaction and restart-safe cleanup through the shared signal
  compactor. Flat manifests preserve retirement tombstones; retention-managed
  manifests fence publication and reclaim metadata through immutable pages.
  """
  alias Pulse.Storage.S3.SignalCompactor

  def compact(tenant, config, opts \\ []),
    do: SignalCompactor.compact(tenant, Map.put(config, :compaction_signal, :metrics), opts)

  def cleanup(tenant, config, opts \\ []),
    do: SignalCompactor.cleanup(tenant, Map.put(config, :compaction_signal, :metrics), opts)

  def select(manifest, opts \\ []), do: SignalCompactor.select(manifest, opts)
end
