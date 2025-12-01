defmodule Tuist.IngestRepo.Migrations.CreateTestCasesTable do
  use Ecto.Migration

  def up do
    create table(:test_cases,
             primary_key: false,
             engine: "ReplacingMergeTree(inserted_at)",
             options: "ORDER BY (project_id, module_name, suite_name, name, id)"
           ) do
      add :id, :uuid, null: false
      add :name, :string, null: false
      add :module_name, :string, null: false, default: ""
      add :suite_name, :string, null: false, default: ""
      add :project_id, :Int64, null: false
      add :last_status, :"Enum8('success' = 0, 'failure' = 1, 'skipped' = 2)", null: false
      add :last_duration, :Int32, null: false, default: 0
      add :last_ran_at, :"DateTime64(6)", null: false
      add :inserted_at, :"DateTime64(6)", default: fragment("now()")
      add :recent_durations, :"Array(Int32)", null: false, default: fragment("[]")
      add :avg_duration, :Int64, null: false, default: 0
    end

    execute("ALTER TABLE test_cases ADD INDEX idx_id (id) TYPE bloom_filter GRANULARITY 4")
  end

  def down do
    drop table(:test_cases)
  end
end
