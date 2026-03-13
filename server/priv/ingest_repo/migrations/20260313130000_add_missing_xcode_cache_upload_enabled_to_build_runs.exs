defmodule Tuist.IngestRepo.Migrations.AddMissingXcodeCacheUploadEnabledToBuildRuns do
  @moduledoc """
  Re-adds xcode_cache_upload_enabled column to build_runs if it was lost during
  the ReplacingMergeTree conversion (EXCHANGE TABLES on replicated ClickHouse
  may not preserve columns added between table creation and exchange).
  """
  use Ecto.Migration
  alias Tuist.IngestRepo

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    {:ok, %{rows: rows}} =
      IngestRepo.query(
        """
        SELECT count()
        FROM system.columns
        WHERE database = currentDatabase() AND table = 'build_runs' AND name = 'xcode_cache_upload_enabled'
        """,
        []
      )

    case rows do
      [[0]] ->
        IngestRepo.query!(
          "ALTER TABLE build_runs ADD COLUMN IF NOT EXISTS xcode_cache_upload_enabled Bool DEFAULT false"
        )

      _ ->
        :ok
    end
  end

  def down do
    :ok
  end
end
