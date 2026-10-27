defmodule Tuist.IngestRepo.Migrations.CreateTestRunErrorsTable do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute("""
    CREATE TABLE IF NOT EXISTS test_run_errors
    (
      `id` UUID,
      `test_run_id` UUID,
      `project_id` Int64,
      `module_name` String,
      `message` String,
      `inserted_at` DateTime64(6) DEFAULT now()
    )
    ENGINE = MergeTree()
    PARTITION BY toYYYYMM(inserted_at)
    ORDER BY (test_run_id, inserted_at, id)
    """)
  end

  def down do
    drop table(:test_run_errors)
  end
end
