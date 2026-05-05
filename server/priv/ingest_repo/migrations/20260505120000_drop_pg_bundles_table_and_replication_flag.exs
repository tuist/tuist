defmodule Tuist.IngestRepo.Migrations.DropPgBundlesTableAndReplicationFlag do
  @moduledoc """
  Drops the `bundles` table and the `bundles.replicated_to_ch` column from
  PostgreSQL.

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

    Repo.query!("DROP TABLE IF EXISTS bundles")
  end

  def down do
    case Repo.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    Repo.query!("""
    CREATE TABLE bundles (
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

    Repo.query!("CREATE INDEX bundles_project_id_git_ref_index ON bundles (project_id, git_ref)")
  end
end
