defmodule Tuist.Repo.Migrations.RemoveFieldsFromAppBuilds do
  use Ecto.Migration

  def change do
    alter table(:app_builds) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :display_name, :string
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :bundle_identifier, :string
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :version, :string
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :git_branch, :string
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :git_commit_sha, :string
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :project_id, :integer
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :ran_by_account_id, :integer
    end
  end
end
