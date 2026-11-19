defmodule Tuist.IngestRepo.Migrations.AddGuaranteedCpuMilliToSandboxEvents do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  # The CPU a sandbox was guaranteed, which its account's concurrency counts.
  # Rows before it hold 0 and count their vCPUs.
  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    ALTER TABLE sandbox_events
    ADD COLUMN IF NOT EXISTS guaranteed_cpu_milli UInt32 DEFAULT 0
    """)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("ALTER TABLE sandbox_events DROP COLUMN IF EXISTS guaranteed_cpu_milli")
  end
end
