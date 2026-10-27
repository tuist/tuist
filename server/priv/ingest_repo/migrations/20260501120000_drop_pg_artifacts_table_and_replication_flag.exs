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
    # The PostgreSQL repo is not started during ClickHouse migrations, and Ecto
    # discards the task each migration runs in, so start it through
    # `Ecto.Migrator.with_repo/2` instead of linking it to that task.
    {:ok, _, _} =
      Ecto.Migrator.with_repo(Repo, fn _repo ->
        Repo.query!("ALTER TABLE bundles DROP COLUMN IF EXISTS artifacts_replicated_to_ch")
        Repo.query!("DROP TABLE IF EXISTS artifacts")
      end)
  end

  def down do
    {:ok, _, _} =
      Ecto.Migrator.with_repo(Repo, fn _repo ->
        recreate_artifacts_table()
      end)
  end

  defp recreate_artifacts_table do
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
