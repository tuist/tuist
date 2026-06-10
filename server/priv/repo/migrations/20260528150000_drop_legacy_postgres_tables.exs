defmodule Tuist.Repo.Migrations.DropLegacyPostgresTables do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  # Vestigial Postgres tables the current Elixir app no longer reads or
  # writes, removed so the in-cluster CloudNativePG schema starts clean:
  #
  #   * runner_assignments — replaced by runner_claims / runner_sessions.
  #   * que_*, ar_internal_metadata — Rails/Que leftovers from the pre-Elixir
  #     server, unused by the current app.
  #
  # The `build_runs`, `bundles`, and `artifacts` tables are also dead from
  # the app's point of view but stay alive through this migration: their
  # historical rows still need to drain into ClickHouse via the IngestRepo
  # backfills (`20260211124936_backfill_build_runs_from_postgres`,
  # `20260428120000_backfill_artifacts_from_postgres`,
  # `20260504120001_backfill_bundles_from_postgres`), and
  # `Tuist.Release.migrate/0` runs every `Tuist.Repo` migration before
  # any `Tuist.IngestRepo` migration — dropping the source tables here
  # would either lose the data or break the backfill. Their drops live
  # alongside the backfills under `priv/ingest_repo/migrations/` so they
  # run *after* the copy has finished.
  #
  # No live table references any of these: the only inbound foreign keys are
  # within the dead set itself (que_scheduler_audit_enqueued ->
  # que_scheduler_audit), which a single DROP TABLE resolves. IF EXISTS
  # keeps this a no-op for whichever tables a given environment lacks.
  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    DROP TABLE IF EXISTS
      runner_assignments,
      ar_internal_metadata,
      que_jobs,
      que_lockers,
      que_scheduler_audit,
      que_scheduler_audit_enqueued,
      que_values
    CASCADE
    """)
  end

  def down do
    raise Ecto.MigrationError,
      message: "Irreversible: legacy tables removed with the Rails-era server."
  end
end
