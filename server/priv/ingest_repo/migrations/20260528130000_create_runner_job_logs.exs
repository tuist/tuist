defmodule Tuist.IngestRepo.Migrations.CreateRunnerJobLogs do
  use Ecto.Migration

  # Per-line log storage for runner jobs — one row per line of the
  # GitHub Actions runner's stdout, captured by the in-VM/in-Pod log
  # shipper and streamed to the server.
  #
  # ClickHouse (not object storage) because every read is a
  # time-windowed, ordered scan over append-only data: a single
  # step's output is `WHERE workflow_job_id = ? AND ts >= ? AND ts < ?`,
  # which the order key serves directly, and the live tail / full
  # stream are `ORDER BY line_number` ranges. Object storage would
  # force download-and-scan for per-step slicing and can't be read
  # mid-run.
  #
  # ReplacingMergeTree on `(workflow_job_id, line_number)` makes the
  # shipper's at-least-once chunk delivery idempotent: a retried
  # chunk re-inserts identical `(job, line_number)` rows that the
  # merge collapses, with `inserted_at` as the version column.
  #
  # 90-day TTL mirrors GitHub Actions' own default log retention so
  # the customer view stays at parity with what GitHub would show.
  def up do
    create table(:runner_job_logs,
             primary_key: false,
             engine: "ReplacingMergeTree(inserted_at)",
             options:
               "PARTITION BY toYYYYMM(ts) ORDER BY (workflow_job_id, line_number) TTL toDateTime(inserted_at) + INTERVAL 90 DAY"
           ) do
      add :workflow_job_id, :Int64, null: false
      add :account_id, :Int64, null: false

      # Monotonic per-job sequence assigned by the shipper. Doubles
      # as the stable display order and the RMT dedup key.
      add :line_number, :UInt32, null: false

      # Per-line timestamp from the runner output (GitHub prefixes
      # every line with an ISO-8601 stamp). Drives per-step slicing.
      add :ts, :"DateTime64(6, 'UTC')", null: false, default: fragment("now64(6)")

      add :message, :string, null: false, default: ""

      add :inserted_at, :"DateTime64(6, 'UTC')", null: false, default: fragment("now64(6)")
    end
  end

  def down do
    drop table(:runner_job_logs)
  end
end
