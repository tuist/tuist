defmodule Tuist.IngestRepo.Migrations.RestorePgBundlesForRollout do
  @moduledoc """
  Temporarily restores the PostgreSQL `bundles` table so that server pods still
  running pre-phase-4 code can complete their Repo queries without crashing.

  The pre-phase-4 code calls `Repo.one()` (PostgreSQL) inside
  `Bundles.last_project_bundle/2`. With the table absent those queries raise
  `Postgrex.Error: relation "bundles" does not exist`, which causes the
  `Tuist.Alerts.Workers.AlertWorker` Oban jobs to fail every 10 minutes.

  An empty table is sufficient: Ecto returns `nil` for missing rows, and every
  call-site that reads from `last_project_bundle` already handles `nil` gracefully.

  Lives in the IngestRepo migrations directory so it runs after the drop
  migration (20260505120000), ensuring the table ends up present regardless of
  whether the drop had already been applied on a given environment.

  This migration and the resulting table can be removed once the phase-4 rollout
  is fully complete and no pre-phase-4 pods remain in service.
  """

  use Ecto.Migration

  alias Tuist.Repo

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    case Repo.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    Repo.query!("""
    CREATE TABLE IF NOT EXISTS bundles (
      id uuid PRIMARY KEY,
      app_bundle_id varchar(255) NOT NULL,
      name varchar(255) NOT NULL,
      install_size integer NOT NULL,
      download_size integer,
      git_branch varchar(255),
      git_commit_sha varchar(255),
      git_ref varchar(255),
      supported_platforms integer[] NOT NULL DEFAULT '{}',
      version varchar(255) NOT NULL,
      type integer NOT NULL,
      project_id bigint NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
      uploaded_by_account_id bigint REFERENCES accounts(id) ON DELETE SET NULL,
      replicated_to_ch boolean NOT NULL DEFAULT true,
      inserted_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now()
    )
    """)

    Repo.query!(
      "CREATE INDEX IF NOT EXISTS bundles_project_id_git_ref_index ON bundles (project_id, git_ref)"
    )
  end

  def down do
    case Repo.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    Repo.query!("DROP TABLE IF EXISTS bundles")
  end
end
