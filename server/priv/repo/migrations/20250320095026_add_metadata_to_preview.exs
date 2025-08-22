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
    drop_if_exists index(:previews, [:project_id, :git_branch])

    alter table(:previews) do
      remove_if_exists :ran_by_account_id, references(:accounts, on_delete: :nilify_all)
      remove_if_exists :git_commit_sha, :string
      remove_if_exists :git_branch, :string
    end
  end
end
