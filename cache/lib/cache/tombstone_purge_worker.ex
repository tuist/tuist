defmodule Cache.TombstonePurgeWorker do
  @moduledoc false

  use Oban.Worker, queue: :maintenance, max_attempts: 1

  alias Cache.Config
  alias Cache.DistributedKV.Cleanup

  @telemetry_event [:cache, :kv, :tombstone_purge, :complete]

  @impl Oban.Worker
  def perform(_job) do
    if Config.distributed_kv_enabled?() do
      started_at = System.monotonic_time(:millisecond)
      purged = Cleanup.purge_tombstones_older_than(Config.distributed_kv_tombstone_retention_days())

      :telemetry.execute(
        @telemetry_event,
        %{entries_purged: purged, duration_ms: System.monotonic_time(:millisecond) - started_at},
        %{}
      )
    end

    :ok
  end
end
