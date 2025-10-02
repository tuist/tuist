defmodule Tuist.Repo.Migrations.AddGithubAppInstallationsTable do
  use Ecto.Migration

  def change do
    create table(:github_app_installations, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :installation_id, :string, null: false
      add :html_url, :string

      timestamps(type: :timestamptz)
    end

    create unique_index(:github_app_installations, [:account_id])
    create unique_index(:github_app_installations, [:installation_id])
  end
end
