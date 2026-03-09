defmodule Tuist.IngestRepo.Migrations.FixTestCaseRunsNullableColumns do
  @moduledoc """
  Ensures test_case_runs columns are non-nullable.

  Migration 100001 handles this, but in CI the MODIFY COLUMN statements
  may be skipped due to stale _build cache loading an old version of that
  migration module. Running them here (in a fresh module) guarantees they
  execute. If the columns are already non-nullable, these are no-ops.
  """
  use Ecto.Migration
  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # Kill stuck mutations from previous failed deploy attempts.
    # These will never complete on their own because the originating
    # process crashed mid-migration.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    KILL MUTATION
    WHERE database = currentDatabase()
      AND table = 'test_case_runs'
      AND is_done = 0
    """

    # Wait for any pending mutations from previous migrations to finish
    # before submitting more. ClickHouse rejects new mutations when the
    # queue is too deep (CANNOT_ASSIGN_ALTER).
    wait_for_mutations("test_case_runs")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs MODIFY COLUMN project_id Int64 DEFAULT 0 SETTINGS mutations_sync = 1"
    wait_for_mutations("test_case_runs")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs MODIFY COLUMN project_id REMOVE DEFAULT SETTINGS mutations_sync = 1"
    wait_for_mutations("test_case_runs")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs MODIFY COLUMN ran_at DateTime64(6) DEFAULT toDateTime64('1970-01-01 00:00:00', 6) SETTINGS mutations_sync = 1"
    wait_for_mutations("test_case_runs")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs MODIFY COLUMN ran_at REMOVE DEFAULT SETTINGS mutations_sync = 1"
  end

  def down do
    :ok
  end

  defp wait_for_mutations(table, retries \\ 30) do
    {:ok, %{rows: [[count]]}} =
      repo().query(
        "SELECT count() FROM system.mutations WHERE database = currentDatabase() AND table = {table:String} AND is_done = 0",
        %{table: table}
      )

    if count > 0 and retries > 0 do
      Logger.info("Waiting for #{count} pending mutation(s) on #{table}...")
      Process.sleep(2_000)
      wait_for_mutations(table, retries - 1)
    end
  end
end
