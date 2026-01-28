defmodule Cache.SQLiteBuffer.PromExPlugin do
  use PromEx.Plugin

  @duration_buckets [1, 5, 10, 25, 50, 100, 250, 500, 1000, 2000, 5000]
  @buffers [Cache.KeyValueBuffer, Cache.CacheArtifactsBuffer, Cache.S3TransfersBuffer]

  @impl true
  def event_metrics(_opts) do
    Event.build(:cache_sqlite_buffer_event_metrics, [
      counter([:tuist_cache, :sqlite_writer, :retries, :total],
        event_name: [:cache, :sqlite_writer, :retry],
        description: "SQLite writer retries due to busy database.",
        tags: [:operation, :buffer],
        tag_values: fn metadata ->
          %{
            operation: to_string(Map.get(metadata, :operation, :unknown)),
            buffer: to_string(Map.get(metadata, :buffer, :unknown))
          }
        end
      ),
      distribution([:tuist_cache, :sqlite_writer, :flush, :duration, :ms],
        event_name: [:cache, :sqlite_writer, :flush],
        measurement: :duration_ms,
        unit: :millisecond,
        description: "SQLite writer flush durations.",
        tags: [:operation, :buffer],
        tag_values: fn metadata ->
          %{
            operation: to_string(Map.get(metadata, :operation, :unknown)),
            buffer: to_string(Map.get(metadata, :buffer, :unknown))
          }
        end,
        reporter_options: [buckets: @duration_buckets]
      ),
      sum([:tuist_cache, :sqlite_writer, :flush, :batch_size],
        event_name: [:cache, :sqlite_writer, :flush],
        measurement: :batch_size,
        description: "SQLite writer rows flushed per operation.",
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
      :cache_sqlite_buffer_polling_metrics,
      poll_rate,
      {__MODULE__, :execute_queue_metrics, []},
      [
        last_value([:tuist_cache, :sqlite_writer, :pending, :total],
          event_name: [:cache, :prom_ex, :sqlite_writer, :queue],
          measurement: :total,
          description: "Total queued SQLite writer entries."
        ),
        last_value([:tuist_cache, :sqlite_writer, :pending, :key_values],
          event_name: [:cache, :prom_ex, :sqlite_writer, :queue],
          measurement: :key_values,
          description: "Queued key-value upserts."
        ),
        last_value([:tuist_cache, :sqlite_writer, :pending, :cas_artifacts],
          event_name: [:cache, :prom_ex, :sqlite_writer, :queue],
          measurement: :cas_artifacts,
          description: "Queued CAS artifact updates and deletes."
        ),
        last_value([:tuist_cache, :sqlite_writer, :pending, :s3_transfers],
          event_name: [:cache, :prom_ex, :sqlite_writer, :queue],
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
          nil ->
            acc

          _pid ->
            Map.put(acc, buffer, buffer.queue_stats())
        end
      end)

    if map_size(stats_by_buffer) == 0 do
      :ok
    else
      key_values = Map.get(stats_by_buffer[Cache.KeyValueBuffer] || %{}, :key_values, 0)
      cas_artifacts = Map.get(stats_by_buffer[Cache.CacheArtifactsBuffer] || %{}, :cas_artifacts, 0)
      s3_transfers = Map.get(stats_by_buffer[Cache.S3TransfersBuffer] || %{}, :s3_transfers, 0)

      :telemetry.execute(
        [:cache, :prom_ex, :sqlite_writer, :queue],
        %{
          total: key_values + cas_artifacts + s3_transfers,
          key_values: key_values,
          cas_artifacts: cas_artifacts,
          s3_transfers: s3_transfers
        },
        %{}
      )
    end
  end
end
