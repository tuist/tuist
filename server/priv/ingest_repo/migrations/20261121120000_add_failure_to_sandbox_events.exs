defmodule Tuist.IngestRepo.Migrations.AddFailureToSandboxEvents do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  # What a `failed` row failed with, on which node and template, so the
  # failure outlives the sandbox row, which a retry or a delete removes.
  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    ALTER TABLE sandbox_events
    ADD COLUMN IF NOT EXISTS error_message String DEFAULT '',
    ADD COLUMN IF NOT EXISTS node_name LowCardinality(String) DEFAULT '',
    ADD COLUMN IF NOT EXISTS template LowCardinality(String) DEFAULT ''
    """)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    ALTER TABLE sandbox_events
    DROP COLUMN IF EXISTS error_message,
    DROP COLUMN IF EXISTS node_name,
    DROP COLUMN IF EXISTS template
    """)
  end
end
