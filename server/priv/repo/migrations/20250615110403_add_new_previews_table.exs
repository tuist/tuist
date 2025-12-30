defmodule Tuist.Repo.Migrations.R do
  use Ecto.Migration

  def change do
    create table(:previews, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :created_by_account_id, references(:accounts, on_delete: :delete_all)
      add :display_name, :string
      add :bundle_identifier, :string
      add :version, :string
      add :git_branch, :string
      add :git_commit_sha, :string
      add :git_ref, :string
      add :supported_platforms, {:array, :integer}, default: []
      add :visibility, :integer, default: 1

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:previews, [:created_by_account_id])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:previews, [:git_commit_sha])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:previews, [:git_branch])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:previews, [:bundle_identifier])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:previews, [:project_id, :git_ref])
  end
end
