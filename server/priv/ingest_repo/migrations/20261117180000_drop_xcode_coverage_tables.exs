defmodule Tuist.IngestRepo.Migrations.DropXcodeCoverageTables do
  @moduledoc """
  Drops `xcode_coverage_files` and `xcode_coverage_runs`, the Xcode-only
  coverage tables that `coverage_files` and `coverage_runs` replaced
  (`20260916150000_create_coverage_tables`). Nothing has read or written them
  since, and no data was copied from them, so the running release doesn't
  notice.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo

  @disable_ddl_transaction true
  @disable_migration_lock true

  # `SYNC` because on a `Replicated` database a plain DROP is queued.
  def up do
    for table <- ~w(xcode_coverage_files xcode_coverage_runs) do
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      # excellent_migrations:safety-assured-for-next-line table_dropped
      IngestRepo.query!("DROP TABLE IF EXISTS #{table} SYNC", [], timeout: :infinity)
    end
  end

  def down, do: :ok
end
