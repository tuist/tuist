defmodule Tuist.Repo.Migrations.AddFileChangesToGitCommitListings do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  # Where a listed commit's file changes are written in ClickHouse
  # (`git_file_changes`), until when they are kept and how many rows they
  # are: the place they were written for, which a reader compares with the
  # commit's current one.
  def change do
    alter table(:git_commit_listings) do
      add :changes_ref_id, :bigint
      add :changes_position, :integer
      add :changes_expires_at, :timestamptz
      add :changes_count, :integer
    end

    create index(:git_commit_listings, [:changes_ref_id, :changes_position],
             where: "changes_ref_id IS NOT NULL",
             concurrently: true
           )
  end
end
