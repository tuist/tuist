defmodule Tuist.IngestRepo.Migrations.BackfillArtifactsFromPostgres do
  @moduledoc """
  Phase 2 of the PG → CH `artifacts` migration. Drains every bundle whose
  artifacts haven't been replicated yet (`artifacts_replicated_to_ch =
  false`) into ClickHouse. See `Tuist.Bundles.ArtifactBackfill` for the
  per-batch logic, idempotency guarantees, and rationale.

  The backfill volume (~225M rows on production) means this is a
  long-running migration. It is wrapped in a `TUIST_SKIP_DATA_MIGRATION`
  escape hatch so ephemeral or fresh environments can skip it.
  """

  use Ecto.Migration

  alias Tuist.Bundles.ArtifactBackfill
  alias Tuist.Repo

  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    if System.get_env("TUIST_SKIP_DATA_MIGRATION") in ["true", "1"] do
      Logger.info("Skipping artifact backfill (TUIST_SKIP_DATA_MIGRATION set)")
      :ok
    else
      # The PostgreSQL repo is not started during ClickHouse migrations.
      case Repo.start_link() do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
      end

      ArtifactBackfill.run()
      :ok
    end
  end

  def down, do: :ok
end
