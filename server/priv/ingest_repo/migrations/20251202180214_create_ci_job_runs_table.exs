defmodule Tuist.IngestRepo.Migrations.CreateCIJobRunsTable do
  use Ecto.Migration

  def up do
    create table(:ci_job_runs,
             primary_key: false,
             engine: "MergeTree",
             options: "PARTITION BY toYYYYMM(inserted_at) ORDER BY (project_id, started_at, id)"
           ) do
      add :id, :uuid, null: false
      add :project_id, :Int64, null: false

      add :workflow_id, :string, null: false
      add :workflow_name, :string, null: false
      add :job_id, :string, null: false
      add :job_name, :string, null: false

      add :git_branch, :string, null: false
      add :git_commit_sha, :string, null: false
      add :git_ref, :string

      add :runner_machine, :string, null: false
      add :runner_configuration, :string

      add :status,
          :"Enum8('pending' = 0, 'running' = 1, 'success' = 2, 'failure' = 3, 'cancelled' = 4)",
          null: false

      add :duration_ms, :"Nullable(Int32)"
      add :started_at, :"DateTime64(6)", null: false
      add :inserted_at, :"DateTime64(6)", default: fragment("now()"), null: false
    end

    execute(
      "ALTER TABLE ci_job_runs ADD INDEX idx_project_id (project_id) TYPE bloom_filter GRANULARITY 4"
    )

    execute(
      "ALTER TABLE ci_job_runs ADD INDEX idx_workflow_id (workflow_id) TYPE bloom_filter GRANULARITY 4"
    )

    execute(
      "ALTER TABLE ci_job_runs ADD INDEX idx_job_id (job_id) TYPE bloom_filter GRANULARITY 4"
    )

    execute(
      "ALTER TABLE ci_job_runs ADD INDEX idx_git_branch (git_branch) TYPE bloom_filter GRANULARITY 4"
    )

    execute(
      "ALTER TABLE ci_job_runs ADD INDEX idx_git_commit_sha (git_commit_sha) TYPE bloom_filter GRANULARITY 4"
    )

    execute("ALTER TABLE ci_job_runs ADD INDEX idx_status (status) TYPE set(5) GRANULARITY 1")

    execute(
      "ALTER TABLE ci_job_runs ADD INDEX idx_duration_ms (duration_ms) TYPE minmax GRANULARITY 4"
    )

    execute(
      "ALTER TABLE ci_job_runs ADD INDEX idx_started_at (started_at) TYPE minmax GRANULARITY 4"
    )
  end

  def down do
    drop table(:ci_job_runs)
  end
end
