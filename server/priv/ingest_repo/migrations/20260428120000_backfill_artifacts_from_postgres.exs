defmodule Tuist.IngestRepo.Migrations.BackfillArtifactsFromPostgres do
  @moduledoc """
  Phase 2 of the PG → CH `artifacts` migration. Drains every bundle whose
  artifacts haven't been replicated yet (`artifacts_replicated_to_ch =
  false`) into ClickHouse. See `Tuist.Bundles.ArtifactBackfill` for the
  per-batch logic, idempotency guarantees, and rationale.
  """

  use Ecto.Migration

  alias Tuist.Bundles.ArtifactBackfill
  alias Tuist.Repo

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # The PostgreSQL repo is not started during ClickHouse migrations.
    case Repo.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    ArtifactBackfill.run()
    :ok
  end

  def down, do: :ok
end
