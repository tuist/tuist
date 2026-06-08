defmodule Tuist.IngestRepo.Migrations.DropPgBuildRunsTable do
  @moduledoc """
  Drops the `build_runs` table from PostgreSQL after the ClickHouse
  backfill (`20260211124936_backfill_build_runs_from_postgres`) has
  drained its rows. On Supabase this is the lone TimescaleDB
  hypertable, so the drop also clears the path for the in-cluster
  CloudNativePG schema to run without the timescaledb extension.

  Lives in the IngestRepo migrations directory because
  `Tuist.Release.migrate/0` runs every `Tuist.Repo` migration before
  any `Tuist.IngestRepo` migration. Putting the drop here guarantees it
  runs *after* the backfill that copies the rows into ClickHouse.
  """

  use Ecto.Migration

  alias Tuist.Repo

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # PostgreSQL repo is not started during ClickHouse migrations.
    case Repo.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    Repo.query!("DROP TABLE IF EXISTS build_runs CASCADE")
  end

  def down do
    raise Ecto.MigrationError,
      message: "Irreversible: build analytics live in ClickHouse now."
  end
end
