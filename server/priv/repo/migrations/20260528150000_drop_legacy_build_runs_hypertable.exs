defmodule Tuist.Repo.Migrations.DropLegacyBuildRunsHypertable do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  # Build analytics live in ClickHouse: `Tuist.Builds.Build` is a
  # ClickHouse-backed schema and nothing in the app reads or writes the
  # Postgres `build_runs` table anymore. On Supabase it survives only as a
  # legacy TimescaleDB hypertable (the sole hypertable in the database; the
  # conversion was done Supabase-side, never in a repo migration, which is
  # why it's absent from the dev schema).
  #
  # Drop the dead table so the canonical Postgres schema doesn't carry it
  # onto the CloudNativePG data plane. We intentionally do NOT drop the
  # timescaledb extension: nothing uses it once build_runs is gone, dropping
  # it on Supabase needs privileges the managed `postgres` role may not have,
  # and the only place it would otherwise leak is the schema dump for CNPG —
  # which filters the single `CREATE EXTENSION timescaledb` line instead. The
  # unused extension on Supabase is harmless and goes away when Supabase is
  # decommissioned post-cutover.
  #
  # IF EXISTS keeps this a no-op in dev/test, where the table never existed.
  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("DROP TABLE IF EXISTS build_runs CASCADE")
  end

  def down do
    raise Ecto.MigrationError,
      message:
        "Irreversible: build_runs was a legacy TimescaleDB hypertable superseded by ClickHouse build analytics."
  end
end
