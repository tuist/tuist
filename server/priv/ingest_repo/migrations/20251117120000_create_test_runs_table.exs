defmodule Tuist.IngestRepo.Migrations.CreateTestRunsTable do
  use Ecto.Migration

  def up do
    create table(:test_runs,
             primary_key: false,
             engine: "MergeTree",
             options: "PARTITION BY toYYYYMM(inserted_at) ORDER BY (project_id, ran_at, id)"
           ) do
      add :id, :uuid, null: false
      add :project_id, :Int64, null: false
      add :duration, :Int32, null: false
      add :macos_version, :string, null: false
      add :xcode_version, :string, null: false
      add :is_ci, :boolean, null: false
      add :model_identifier, :string
      add :scheme, :string
      add :status, :"Enum8('success' = 0, 'failure' = 1)", null: false
      add :git_branch, :string
      add :git_commit_sha, :string
      add :git_ref, :string
      add :account_id, :Int64, null: false
      add :ran_at, :"DateTime64(6)", null: false
      add :inserted_at, :"DateTime64(6)", default: fragment("now()")
    end

    # Add secondary indices for common query patterns
    execute("ALTER TABLE test_runs ADD INDEX idx_duration (duration) TYPE minmax GRANULARITY 4")
    execute("ALTER TABLE test_runs ADD INDEX idx_status (status) TYPE set(2) GRANULARITY 1")
    execute("ALTER TABLE test_runs ADD INDEX idx_scheme (scheme) TYPE bloom_filter GRANULARITY 4")
  end

  def down do
    drop table(:test_runs)
  end
end
