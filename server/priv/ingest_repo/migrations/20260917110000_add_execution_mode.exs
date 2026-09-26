defmodule Tuist.IngestRepo.Migrations.AddExecutionMode do
  @moduledoc """
  Whether tests executed in parallel or serially, per run and per target, so
  the serial cost of per-test attribution can be weighed against history from
  the first coverage runs on.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute(
      "ALTER TABLE test_runs ADD COLUMN IF NOT EXISTS execution_mode LowCardinality(String) DEFAULT ''"
    )

    execute(
      "ALTER TABLE test_module_runs ADD COLUMN IF NOT EXISTS execution_mode LowCardinality(String) DEFAULT ''"
    )
  end

  def down do
    execute("ALTER TABLE test_module_runs DROP COLUMN IF EXISTS execution_mode")
    execute("ALTER TABLE test_runs DROP COLUMN IF EXISTS execution_mode")
  end
end
