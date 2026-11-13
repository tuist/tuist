defmodule Tuist.Repo.Migrations.AddStagedToGitCommitListings do
  use Ecto.Migration

  # A commit's file changes can be written from a coverage-based selection
  # diff against a written commit, without its files ever being uploaded to
  # ClickHouse `git_commit_files`. Its listing row says so, so nothing reads
  # or rewrites the commit from files that were never staged.
  def change do
    alter table(:git_commit_listings) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :staged, :boolean, null: false, default: true
    end
  end
end
