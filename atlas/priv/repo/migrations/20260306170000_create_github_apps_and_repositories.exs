defmodule Atlas.Repo.Migrations.CreateGitHubAppsAndRepositories do
  use Ecto.Migration

  def change do
    create table(:github_apps, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :webhook_secret, :string, null: false

      timestamps()
    end

    create table(:github_repositories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :owner, :string, null: false
      add :repo, :string, null: false

      add :github_app_id, references(:github_apps, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps()
    end

    create unique_index(:github_repositories, [:owner, :repo, :github_app_id])
    create index(:github_repositories, [:github_app_id])
  end
end
