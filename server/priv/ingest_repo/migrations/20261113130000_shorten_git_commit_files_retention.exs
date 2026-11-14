defmodule Tuist.IngestRepo.Migrations.ShortenGitCommitFilesRetention do
  @moduledoc """
  A commit's uploaded listing is now only where its file changes
  (`git_file_changes`) are written from, minutes after it arrives, so its
  rows are kept for two days (`Tuist.GitHistory.listing_retention_days/0`)
  instead of with the coverage file detail.
  """
  use Ecto.Migration

  alias Tuist.Environment

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("ALTER TABLE git_commit_files MODIFY TTL toDateTime(inserted_at) + INTERVAL 2 DAY")
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "ALTER TABLE git_commit_files MODIFY TTL toDateTime(inserted_at) + INTERVAL #{Environment.coverage_retention_days().files} DAY"
    )
  end
end
