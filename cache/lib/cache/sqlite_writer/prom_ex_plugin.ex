defmodule Cache.SQLiteWriter.PromExPlugin do
  use PromEx.Plugin

  @duration_buckets [1, 5, 10, 25, 50, 100, 250, 500, 1000, 2000, 5000]

  @impl true
  def event_metrics(_opts) do
    Event.build(:cache_sqlite_writer_event_metrics, [
      counter([:tuist_cache, :sqlite_writer, :retries, :total],
        event_name: [:cache, :sqlite_writer, :retry],
        description: "SQLite writer retries due to busy database.",
        tags: [:operation],
        tag_values: fn metadata -> %{operation: to_string(Map.get(metadata, :operation, :unknown))} end
      ),
      distribution([:tuist_cache, :sqlite_writer, :flush, :duration, :ms],
        event_name: [:cache, :sqlite_writer, :flush],
        measurement: :duration_ms,
        unit: :millisecond,
        description: "SQLite writer flush durations.",
        tags: [:operation],
        tag_values: fn metadata -> %{operation: to_string(Map.get(metadata, :operation, :unknown))} end,
        reporter_options: [buckets: @duration_buckets]
      ),
      sum([:tuist_cache, :sqlite_writer, :flush, :batch_size],
        event_name: [:cache, :sqlite_writer, :flush],
        measurement: :batch_size,
        description: "SQLite writer rows flushed per operation.",
        tags: [:operation],
        tag_values: fn metadata -> %{operation: to_string(Map.get(metadata, :operation, :unknown))} end
      )
    ])
  end

  @impl true
  def polling_metrics(opts) do
    poll_rate = Keyword.get(opts, :poll_rate, 15_000)

    Polling.build(
      :cache_sqlite_writer_polling_metrics,
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
    case Process.whereis(Cache.SQLiteWriter) do
      nil ->
        :ok

      _pid ->
        stats = Cache.SQLiteWriter.queue_stats()

        :telemetry.execute(
          [:cache, :prom_ex, :sqlite_writer, :queue],
          %{
            total: stats.total,
            key_values: stats.key_values,
            cas_artifacts: stats.cas_artifacts,
            s3_transfers: stats.s3_transfers
          },
          %{}
        )
    end
  end
end
