defmodule Cache.DistributedKV.GCWorker do
  @moduledoc false

  use Oban.Worker, queue: :maintenance, max_attempts: 1

  alias Cache.Config
  alias Cache.DistributedKV.Cleanup

  @telemetry_event [:cache, :kv, :gc, :complete]
  @batch_size 1000
  @max_batches 50

  @impl Oban.Worker
  def perform(_job) do
    if Config.distributed_kv_enabled?() do
      started_at = System.monotonic_time(:millisecond)
      total_deleted = gc_loop(0, 0)

      :telemetry.execute(
        @telemetry_event,
        %{entries_deleted: total_deleted, duration_ms: System.monotonic_time(:millisecond) - started_at},
        %{}
      )
    end

    :ok
  end

  defp gc_loop(total_deleted, batch_count) when batch_count >= @max_batches, do: total_deleted

  defp gc_loop(total_deleted, batch_count) do
    deleted = Cleanup.gc_shared_entries(@batch_size)

    if deleted == 0 do
      total_deleted
    else
      gc_loop(total_deleted + deleted, batch_count + 1)
    end
  end
end
