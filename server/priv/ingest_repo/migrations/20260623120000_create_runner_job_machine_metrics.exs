defmodule Tuist.IngestRepo.Migrations.CreateRunnerJobMachineMetrics do
  use Ecto.Migration

  # Per-sample machine metrics for runner jobs — one row per
  # resource snapshot taken inside the runner Pod/VM while the
  # workflow_job executes, shipped to the server by the runner
  # metrics collector (see `TuistWeb.RunnerJobMetricsController`).
  #
  # ClickHouse (not Postgres) because the only read is a
  # time-ordered scan over a single job's samples
  # (`WHERE workflow_job_id = ? ORDER BY timestamp`), which the
  # order key serves directly, and the data is append-only and
  # high-volume (one row every few seconds per running job).
  # Mirrors `runner_job_logs`: same `(workflow_job_id, ...)` order
  # key, same 90-day TTL matching GitHub Actions log/artifact
  # retention so the customer view stays at parity. Partitioned by
  # insertion month so the TTL drops whole expired parts instead of
  # mutating one ever-growing partition; the partition column matches
  # the TTL column so parts age out together.
  #
  # ReplacingMergeTree on `(workflow_job_id, timestamp)` with
  # `inserted_at` as the version makes the collector's at-least-once
  # delivery idempotent: a re-POSTed batch re-inserts identical
  # `(job, timestamp)` rows that collapse on merge.
  def up do
    create table(:runner_job_machine_metrics,
             primary_key: false,
             engine: "ReplacingMergeTree(inserted_at)",
             options:
               "PARTITION BY toYYYYMM(inserted_at) ORDER BY (workflow_job_id, timestamp) TTL toDateTime(inserted_at) + INTERVAL 90 DAY"
           ) do
      add :workflow_job_id, :Int64, null: false
      add :account_id, :Int64, null: false

      # Epoch seconds (fractional) when the sample was taken inside
      # the runner. Drives the x-axis and the per-step slicing the
      # job detail page overlays on the charts.
      add :timestamp, :Float64, null: false

      add :cpu_usage_percent, :Float32, null: false, default: 0
      # Share of CPU time spent waiting on blocking I/O. Linux-only
      # (macOS has no iowait accounting); 0 on macOS samples.
      add :cpu_iowait_percent, :Float32, null: false, default: 0

      add :memory_used_bytes, :Int64, null: false, default: 0
      add :memory_total_bytes, :Int64, null: false, default: 0

      add :network_bytes_in, :Int64, null: false, default: 0
      add :network_bytes_out, :Int64, null: false, default: 0

      # Filesystem usage of the runner's working volume, for the
      # Storage chart's used/total percentage.
      add :disk_used_bytes, :Int64, null: false, default: 0
      add :disk_total_bytes, :Int64, null: false, default: 0

      add :inserted_at, :"DateTime64(6, 'UTC')", null: false, default: fragment("now64(6)")
    end
  end

  def down do
    drop table(:runner_job_machine_metrics)
  end
end
