defmodule Tuist.Repo.Migrations.DropLegacyPostgresTables do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  # Vestigial Postgres tables the current Elixir app no longer reads or
  # writes, removed so the in-cluster CloudNativePG schema starts clean:
  #
  #   * build_runs — build analytics live in ClickHouse; on Supabase this is
  #     a legacy TimescaleDB hypertable (the only one), so dropping it lets
  #     the CNPG schema run without the timescaledb extension.
  #   * artifacts, bundles — superseded by the ClickHouse bundle analytics;
  #     already dropped from Supabase out-of-band, still created by old
  #     migrations so they linger on a freshly-migrated cluster.
  #   * runner_assignments — replaced by runner_claims / runner_sessions.
  #   * que_*, ar_internal_metadata — Rails/Que leftovers from the pre-Elixir
  #     server, unused by the current app.
  #
  # No live table references any of these: the only inbound foreign keys are
  # within the dead set itself (artifacts -> bundles,
  # que_scheduler_audit_enqueued -> que_scheduler_audit), which a single
  # DROP TABLE resolves. IF EXISTS keeps this a no-op for whichever tables a
  # given environment lacks (dev never had most; CNPG lacks runner_assignments;
  # Supabase already dropped artifacts/bundles). timescaledb stays installed
  # on Supabase (unused once build_runs is gone) and is filtered from the CNPG
  # schema build rather than dropped from under the managed role.
  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("DROP TABLE IF EXISTS build_runs CASCADE")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    DROP TABLE IF EXISTS
      artifacts,
      bundles,
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
      message:
        "Irreversible: legacy tables superseded by ClickHouse (build/bundle analytics) or removed with the Rails-era server."
  end
end
