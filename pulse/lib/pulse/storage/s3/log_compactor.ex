defmodule Pulse.Storage.S3.LogCompactor do
  @moduledoc """
  Bounded native log compaction through shared signal maintenance. Small log
  segments of one hour merge in Rust without materializing records, keeping
  the encoder's schema, `(service, timestamp)` order and writer settings.
  Retention, retirement cleanup and orphan reclamation are shared with the
  other signals.
  """
  alias Pulse.Storage.S3.SignalCompactor

  def maintain(tenant, config, opts \\ []), do: compact(tenant, config, opts)

  # Live tail followers read log segments before they settle into compaction.
  @settle_ms 60_000

  def compact(tenant, config, opts \\ []),
    do:
      SignalCompactor.compact(
        tenant,
        Map.put(config, :compaction_signal, :logs),
        Keyword.put_new(opts, :settle_ms, @settle_ms)
      )

  def cleanup(tenant, config, opts \\ []),
    do: SignalCompactor.cleanup(tenant, Map.put(config, :compaction_signal, :logs), opts)
end
