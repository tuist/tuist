defmodule Tuist.IngestRepo.Migrations.DropOldTestTables do
  @moduledoc """
  Drops the old test tables that were preserved during the ReplacingMergeTree migration.

  These tables were kept as backups after converting to ReplacingMergeTree in
  migration 20260114100000_convert_test_tables_to_replacing_merge_tree.exs.
  """
  use Ecto.Migration
  alias Tuist.IngestRepo

  def up do
    # Use SYNC to ensure drops complete across all ClickHouse Cloud replicas
    IngestRepo.query!("DROP TABLE IF EXISTS test_runs_old SYNC")
    IngestRepo.query!("DROP TABLE IF EXISTS test_module_runs_old SYNC")
    IngestRepo.query!("DROP TABLE IF EXISTS test_suite_runs_old SYNC")
    IngestRepo.query!("DROP TABLE IF EXISTS test_case_runs_old SYNC")
  end

  def down do
    # Cannot restore dropped tables - this is intentionally a no-op
    :ok
  end
end
