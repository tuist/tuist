defmodule Tuist.IngestRepo.Migrations.CreateCIJobMetricsTable do
  use Ecto.Migration

  def up do
    create table(:ci_job_metrics,
             primary_key: false,
             engine: "MergeTree",
             options:
               "PARTITION BY toYYYYMM(inserted_at) ORDER BY (job_run_id, metric_type, timestamp, inserted_at)"
           ) do
      add :id, :uuid, null: false
      add :job_run_id, :uuid, null: false

      add :metric_type,
          :"Enum8('cpu_percent' = 0, 'memory_percent' = 1, 'network_bytes' = 2, 'cpu_io_wait_percent' = 3, 'storage_percent' = 4)",
          null: false

      add :timestamp, :"DateTime64(6)", null: false
      add :value, :Float64, null: false
      add :inserted_at, :"DateTime64(6)", default: fragment("now()"), null: false
    end

    execute(
      "ALTER TABLE ci_job_metrics ADD INDEX idx_job_run_id (job_run_id) TYPE bloom_filter GRANULARITY 4"
    )

    execute(
      "ALTER TABLE ci_job_metrics ADD INDEX idx_metric_type (metric_type) TYPE set(10) GRANULARITY 1"
    )

    execute(
      "ALTER TABLE ci_job_metrics ADD INDEX idx_timestamp (timestamp) TYPE minmax GRANULARITY 4"
    )
  end

  def down do
    drop table(:ci_job_metrics)
  end
end
