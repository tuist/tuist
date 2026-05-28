defmodule Tuist.Repo.Migrations.DropLegacyBuildRunsHypertable do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  # Build analytics live in ClickHouse: `Tuist.Builds.Build` is a
  # ClickHouse-backed schema and nothing in the app reads or writes the
  # Postgres `build_runs` table anymore. It survives only as a legacy
  # TimescaleDB hypertable (the sole hypertable in the database). Drop it,
  # then drop the now-unused timescaledb extension so the Postgres schema is
  # vanilla — required for the CloudNativePG data plane (plain Postgres, no
  # TimescaleDB).
  #
  # IF EXISTS keeps this a no-op in dev/test, where timescaledb was never
  # installed and the table may not exist. Runs outside a transaction:
  # `DROP EXTENSION timescaledb` cannot execute in a transaction that has
  # already touched timescaledb objects.
  @disable_ddl_transaction true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("DROP TABLE IF EXISTS build_runs CASCADE")
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("DROP EXTENSION IF EXISTS timescaledb CASCADE")
  end

  def down do
    raise Ecto.MigrationError,
      message:
        "Irreversible: build_runs was a legacy TimescaleDB hypertable superseded by ClickHouse build analytics."
  end
end
