defmodule Tuist.Repo.Migrations.AddMetadataToPreview do
  use Ecto.Migration

  def up do
    alter table(:previews) do
      add :git_branch, :string
      add :git_commit_sha, :string
      add :ran_by_account_id, references(:accounts, on_delete: :nilify_all)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:previews, [:project_id, :git_branch])
  end

  def down do
    # Table was renamed to app_builds and recreated, nothing to rollback
    :ok
  end
end
