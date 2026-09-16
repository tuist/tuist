defmodule Atlas.Repo.Migrations.AddAppCredentialsToGitHubApps do
  use Ecto.Migration

  def change do
    alter table(:github_apps) do
      add :app_id, :string
      add :private_key, :text
      add :installation_id, :string
    end
  end
end
