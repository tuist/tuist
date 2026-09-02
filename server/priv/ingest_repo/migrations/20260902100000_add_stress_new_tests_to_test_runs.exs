defmodule Tuist.IngestRepo.Migrations.AddStressNewTestsToTestRuns do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    alter table(:test_runs) do
      add :stress_mode, :"LowCardinality(String)", default: ""
      add :stress_outcome, :"LowCardinality(String)", default: ""
      add :stress_skip_reason, :"LowCardinality(String)", default: ""
      add :stress_new_count, :UInt32, default: 0
      add :stress_stressed_count, :UInt32, default: 0
      add :stress_excluded_count, :UInt32, default: 0
      add :stress_inventory_count, :UInt32, default: 0
    end

    execute("""
    CREATE TABLE IF NOT EXISTS test_run_stress_candidates
    (
      `id` UUID,
      `test_run_id` UUID,
      `project_id` Int64,
      `test_case_id` UUID,
      `name` String,
      `suite_name` String,
      `module_name` String,
      `repetitions` UInt16,
      `failed_repetitions` UInt16,
      `outcome` LowCardinality(String),
      `is_quarantined` Bool,
      `inserted_at` DateTime64(6) DEFAULT now()
    )
    ENGINE = MergeTree()
    PARTITION BY toYYYYMM(inserted_at)
    ORDER BY (test_run_id, inserted_at, id)
    """)
  end

  def down do
    drop table(:test_run_stress_candidates)

    alter table(:test_runs) do
      remove :stress_mode
      remove :stress_outcome
      remove :stress_skip_reason
      remove :stress_new_count
      remove :stress_stressed_count
      remove :stress_excluded_count
      remove :stress_inventory_count
    end
  end
end
