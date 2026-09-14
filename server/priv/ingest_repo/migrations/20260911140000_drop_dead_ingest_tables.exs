defmodule Tuist.IngestRepo.Migrations.DropDeadIngestTables do
  use Ecto.Migration

  alias Tuist.IngestRepo

  @disable_ddl_transaction true
  @disable_migration_lock true

  # Leftovers of table rebuilds, each one the staging half of a create-copy-swap
  # that was never cleaned up. Nothing reads any of them: not `lib/`, not the
  # templates, not the CLI. `test_case_runs_by_commit_v2` is the legacy
  # no-scheme table the live `test_case_runs_by_commit` replaced, and the
  # schema's own docs say the drop is owed once the rollout is stable.
  #
  # They were cleared out of the system of record by hand in September, which
  # is why this is overdue rather than new. Doing it by hand does not hold: a
  # database built from this migration history recreates them, so the
  # in-cluster server has them again and has been copying and parity-checking
  # corpses. `build_runs_new` is the one that forced the issue, failing the
  # cutover's parity gate on a value mismatch no repair can clear, on a table
  # that should not exist.
  #
  # `IF EXISTS` because which of these is present depends on when the database
  # was built, and `SYNC` because on a `Replicated` database a plain DROP is
  # queued: without it the next statement can run before the table is gone and
  # the Keeper path is still held.
  @tables ~w(
    build_runs_new
    test_case_runs_new
    test_case_runs_by_commit_v2
    xcode_targets_backup
    xcode_projects_backup
  )

  def up do
    for table <- @tables do
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      # excellent_migrations:safety-assured-for-next-line table_dropped
      IngestRepo.query!("DROP TABLE IF EXISTS #{table} SYNC", [], timeout: :infinity)
    end
  end

  # Not reversible. These hold no data anything reads, and recreating empty
  # shells of rebuild staging tables would put back exactly what this removes.
  def down, do: :ok
end
