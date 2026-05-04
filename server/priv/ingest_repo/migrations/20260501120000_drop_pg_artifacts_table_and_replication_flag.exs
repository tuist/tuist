defmodule Tuist.IngestRepo.Migrations.DropPgArtifactsTableAndReplicationFlag do
  @moduledoc """
  Phase 4 of the PG → CH `artifacts` migration started in #10493 and
  continued in #10509.

  Lives in the IngestRepo migrations directory so it runs after the
  phase-2 backfill (`20260428120000_backfill_artifacts_from_postgres`)
  on fresh DBs that replay every migration from scratch. `mix ecto.migrate`
  iterates configured repos in `:ecto_repos` order — Tuist.Repo first,
  Tuist.IngestRepo second — so a sibling Repo-side migration at any
  timestamp would otherwise drop the column before the backfill could
  replay against it. Same precedent as the backfill itself, which is an
  IngestRepo migration that drives PG via `Tuist.Repo.query!/2`.
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

    Repo.query!("ALTER TABLE bundles DROP COLUMN IF EXISTS artifacts_replicated_to_ch")
    Repo.query!("DROP TABLE IF EXISTS artifacts")
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
