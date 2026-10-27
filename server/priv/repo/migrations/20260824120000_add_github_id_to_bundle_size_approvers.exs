defmodule Tuist.Repo.Migrations.AddGithubIdToBundleSizeApprovers do
  use Ecto.Migration

  def up do
    # A GitHub username can be changed, and the old one becomes available for
    # another account to claim, so authorizing on it lets someone inherit an
    # allowlisted name. The numeric id does not move.
    #
    # The table ships for the first time in this change, so the only rows are
    # local development ones and there is nothing to backfill an id from.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("DELETE FROM bundle_size_approvers")

    alter table(:bundle_size_approvers) do
      # excellent_migrations:safety-assured-for-next-line not_null_added
      add :github_id, :string, null: false
    end

    # The table is empty immediately above, so this cannot block application writes.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:bundle_size_approvers, [:project_id, :github_id])
  end

  def down do
    # Rolling this back returns the table to a shape where nothing reads the
    # column, so dropping it and its index is the point rather than a hazard.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    drop unique_index(:bundle_size_approvers, [:project_id, :github_id])

    alter table(:bundle_size_approvers) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :github_id
    end
  end
end
