defmodule TuistRegistry.SQLiteBuffer.PromExPlugin do
  @moduledoc false
  use PromEx.Plugin

  @duration_buckets [1, 5, 10, 25, 50, 100, 250, 500, 1000, 2000, 5000]
  @buffers [TuistRegistry.CacheArtifactsBuffer, TuistRegistry.S3TransfersBuffer]

  @impl true
  def event_metrics(_opts) do
    Event.build(:tuist_registry_sqlite_buffer_event_metrics, [
      distribution([:tuist_tuist_registry, :sqlite_buffer, :flush, :duration, :ms],
        event_name: [:tuist_registry, :sqlite_buffer, :flush],
        measurement: :duration_ms,
        unit: :millisecond,
        description: "SQLite buffer flush durations.",
        tags: [:operation, :buffer],
        tag_values: fn metadata ->
          %{
            operation: to_string(Map.get(metadata, :operation, :unknown)),
            buffer: to_string(Map.get(metadata, :buffer, :unknown))
          }
        end,
        reporter_options: [buckets: @duration_buckets]
      ),
      sum([:tuist_tuist_registry, :sqlite_buffer, :flush, :batch_size],
        event_name: [:tuist_registry, :sqlite_buffer, :flush],
        measurement: :batch_size,
        description: "SQLite buffer rows flushed per operation.",
        tags: [:operation, :buffer],
        tag_values: fn metadata ->
          %{
            operation: to_string(Map.get(metadata, :operation, :unknown)),
            buffer: to_string(Map.get(metadata, :buffer, :unknown))
          }
        end
      )
    ])
  end

  @impl true
  def polling_metrics(opts) do
    poll_rate = Keyword.get(opts, :poll_rate, 15_000)

    Polling.build(
      :tuist_registry_sqlite_buffer_polling_metrics,
      poll_rate,
      {__MODULE__, :execute_queue_metrics, []},
      [
        last_value([:tuist_tuist_registry, :sqlite_buffer, :pending, :total],
          event_name: [:tuist_registry, :prom_ex, :sqlite_buffer, :queue],
          measurement: :total,
          description: "Total queued SQLite buffer entries."
        ),
        last_value([:tuist_tuist_registry, :sqlite_buffer, :pending, :cache_artifacts],
          event_name: [:tuist_registry, :prom_ex, :sqlite_buffer, :queue],
          measurement: :cache_artifacts,
          description: "Queued registry artifact updates and deletes."
        ),
        last_value([:tuist_tuist_registry, :sqlite_buffer, :pending, :s3_transfers],
          event_name: [:tuist_registry, :prom_ex, :sqlite_buffer, :queue],
          measurement: :s3_transfers,
          description: "Queued S3 transfer inserts and deletes."
        )
      ]
    )
  end

  def execute_queue_metrics do
    stats_by_buffer =
      Enum.reduce(@buffers, %{}, fn buffer, acc ->
        case Process.whereis(buffer) do
          nil -> acc
          _pid -> Map.put(acc, buffer, buffer.queue_stats())
        end
      end)

    if map_size(stats_by_buffer) == 0 do
      :ok
    else
      cache_artifacts = Map.get(stats_by_buffer[TuistRegistry.CacheArtifactsBuffer] || %{}, :cache_artifacts, 0)
      s3_transfers = Map.get(stats_by_buffer[TuistRegistry.S3TransfersBuffer] || %{}, :s3_transfers, 0)

      :telemetry.execute(
        [:tuist_registry, :prom_ex, :sqlite_buffer, :queue],
        %{
          total: cache_artifacts + s3_transfers,
          cache_artifacts: cache_artifacts,
          s3_transfers: s3_transfers
        },
        %{}
      )
    end
  end
end
