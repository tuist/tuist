defmodule Tuist.IngestRepo.Migrations.AddMemoryToSandboxUsageEvents do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  # A running VM's memory at each report (its process's Pss) and what it
  # held past its request over the interval, so sandboxes are billed
  # max(request, use) per GiB-hour.
  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    ALTER TABLE sandbox_usage_events
    ADD COLUMN IF NOT EXISTS used_memory_bytes UInt64 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS excess_memory_mib_ms UInt64 DEFAULT 0
    """)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    ALTER TABLE sandbox_usage_events
    DROP COLUMN IF EXISTS used_memory_bytes,
    DROP COLUMN IF EXISTS excess_memory_mib_ms
    """)
  end
end
