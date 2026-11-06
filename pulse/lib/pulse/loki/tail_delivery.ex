defmodule Pulse.Loki.TailDelivery do
  @moduledoc false

  # Disposable credits, never acknowledged-data authority. Reserve before
  # copying a message into a recipient's mailbox, not after dequeueing it.
  @max_batches 64
  @max_bytes 16 * 1024 * 1024
  @max_single_batch_bytes 32 * 1024 * 1024

  def new, do: :atomics.new(3, signed: true)

  def deliver(pid, credit, tag, records, overflow \\ :drop, bytes \\ nil) do
    if reserve_batch(credit) do
      bytes = bytes || :erlang.external_size(records)
      queued = :atomics.add_get(credit, 2, bytes)

      # Term overhead can make one admitted 16 MiB ingest batch larger than
      # the normal queue credit. Permit one bounded batch in an empty queue,
      # never an unbounded exception or a second concurrently queued batch.
      if queued <= @max_bytes or (queued == bytes and bytes <= @max_single_batch_bytes) do
        send(pid, {tag, credit, bytes, records})
        :ok
      else
        release(credit, bytes)
        overflow(pid, credit, overflow)
      end
    else
      overflow(pid, credit, overflow)
    end
  end

  def close(pid, credit), do: overflow(pid, credit, :close)

  def release(credit, bytes) do
    :atomics.sub(credit, 2, bytes)
    :atomics.sub(credit, 1, 1)
    :ok
  end

  defp reserve_batch(credit) do
    if :atomics.add_get(credit, 1, 1) <= @max_batches do
      true
    else
      :atomics.sub(credit, 1, 1)
      false
    end
  end

  # At most one tiny close notification can accompany a full socket mailbox.
  defp overflow(pid, credit, :close) do
    if :atomics.compare_exchange(credit, 3, 0, 1) == :ok, do: send(pid, :tail_overloaded)
    :dropped
  end

  defp overflow(_pid, _credit, :drop), do: :dropped
end
