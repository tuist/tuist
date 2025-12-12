defmodule Tuist.IngestRepo.Migrations.CreateCIJobStepsTable do
  use Ecto.Migration

  def up do
    create table(:ci_job_steps,
             primary_key: false,
             engine: "MergeTree",
             options:
               "PARTITION BY toYYYYMM(inserted_at) ORDER BY (job_run_id, step_number, inserted_at)"
           ) do
      add :id, :uuid, null: false
      add :job_run_id, :uuid, null: false
      add :step_number, :UInt16, null: false
      add :step_name, :string, null: false

      add :status,
          :"Enum8('pending' = 0, 'running' = 1, 'success' = 2, 'failure' = 3, 'skipped' = 4)",
          null: false

      add :duration_ms, :"Nullable(Int32)"
      add :started_at, :"DateTime64(6)", null: false
      add :finished_at, :"Nullable(DateTime64(6))"
      add :inserted_at, :"DateTime64(6)", default: fragment("now()"), null: false
    end

    execute(
      "ALTER TABLE ci_job_steps ADD INDEX idx_job_run_id (job_run_id) TYPE bloom_filter GRANULARITY 4"
    )

    execute("ALTER TABLE ci_job_steps ADD INDEX idx_status (status) TYPE set(5) GRANULARITY 1")

    execute(
      "ALTER TABLE ci_job_steps ADD INDEX idx_started_at (started_at) TYPE minmax GRANULARITY 4"
    )
  end

  def down do
    drop table(:ci_job_steps)
  end
end
