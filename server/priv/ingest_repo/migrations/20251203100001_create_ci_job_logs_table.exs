defmodule Tuist.IngestRepo.Migrations.CreateCIJobLogsTable do
  use Ecto.Migration

  def up do
    create table(:ci_job_logs,
             primary_key: false,
             engine: "MergeTree",
             options:
               "PARTITION BY toYYYYMM(inserted_at) ORDER BY (step_id, timestamp, inserted_at)"
           ) do
      add :id, :uuid, null: false
      add :step_id, :uuid, null: false
      add :job_run_id, :uuid, null: false
      add :timestamp, :"DateTime64(6)", null: false
      add :message, :string, null: false
      add :stream, :"Enum8('stdout' = 0, 'stderr' = 1)", null: false
      add :inserted_at, :"DateTime64(6)", default: fragment("now()"), null: false
    end

    execute(
      "ALTER TABLE ci_job_logs ADD INDEX idx_step_id (step_id) TYPE bloom_filter GRANULARITY 4"
    )

    execute(
      "ALTER TABLE ci_job_logs ADD INDEX idx_job_run_id (job_run_id) TYPE bloom_filter GRANULARITY 4"
    )

    execute(
      "ALTER TABLE ci_job_logs ADD INDEX idx_timestamp (timestamp) TYPE minmax GRANULARITY 4"
    )
  end

  def down do
    drop table(:ci_job_logs)
  end
end
