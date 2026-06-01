defmodule Tuist.IngestRepo.Migrations.DropPgArtifactsTableAndReplicationFlag do
  @moduledoc """
  Drops the `artifacts` table and the `bundles.artifacts_replicated_to_ch`
  column from PostgreSQL.

  Lives in the IngestRepo migrations directory because `mix ecto.migrate`
  iterates configured repos in `:ecto_repos` order — Tuist.Repo first,
  Tuist.IngestRepo second — so any cross-DB ordering between PG schema
  changes and IngestRepo migrations that touch PG (via
  `Tuist.Repo.query!/2`) needs to be expressed as timestamp ordering
  inside `priv/ingest_repo/migrations/`.
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

    # `DROP COLUMN IF EXISTS` covers the column, not the parent table: if
    # `bundles` itself is gone (dropped by `drop_legacy_postgres_tables`,
    # which CASCADEs the dual-write column with it), the ALTER still
    # raises `undefined_table`. Skip it when the table is missing.
    if postgres_bundles_exists?() do
      Repo.query!("ALTER TABLE bundles DROP COLUMN IF EXISTS artifacts_replicated_to_ch")
    end

    Repo.query!("DROP TABLE IF EXISTS artifacts")
  end

  defp postgres_bundles_exists? do
    {:ok, %{rows: [[result]]}} = Repo.query("SELECT to_regclass('public.bundles')")
    result != nil
  end

  def down do
    case Repo.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    Repo.query!("""
    CREATE TABLE artifacts (
      id uuid PRIMARY KEY,
      artifact_type varchar(255) NOT NULL,
      path varchar(255) NOT NULL,
      size bigint NOT NULL,
      shasum varchar(255) NOT NULL,
      bundle_id uuid NOT NULL REFERENCES bundles(id) ON DELETE CASCADE,
      artifact_id uuid,
      inserted_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now()
    )
    """)

    Repo.query!("CREATE INDEX artifacts_bundle_id_index ON artifacts (bundle_id)")
    Repo.query!("CREATE INDEX artifacts_artifact_id_index ON artifacts (artifact_id)")

    Repo.query!(
      "CREATE INDEX artifacts_bundle_id_artifact_id_index ON artifacts (bundle_id, artifact_id)"
    )

    Repo.query!(
      "CREATE INDEX artifacts_top_level_index ON artifacts (bundle_id) WHERE artifact_id IS NULL"
    )

    Repo.query!(
      "ALTER TABLE bundles ADD COLUMN artifacts_replicated_to_ch boolean NOT NULL DEFAULT true"
    )
  end
end
