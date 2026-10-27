defmodule Tuist.IngestRepo.Migrations.CreateTestRunDestinationsTable do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute("""
    CREATE TABLE IF NOT EXISTS test_run_destinations
    (
      `id` UUID,
      `test_run_id` UUID,
      `name` String,
      `platform` LowCardinality(String),
      `os_version` String,
      `inserted_at` DateTime64(6) DEFAULT now()
    )
    ENGINE = MergeTree()
    PARTITION BY toYYYYMM(inserted_at)
    ORDER BY (test_run_id, inserted_at, id)
    """)
  end

  def down do
    drop table(:test_run_destinations)
  end
end
