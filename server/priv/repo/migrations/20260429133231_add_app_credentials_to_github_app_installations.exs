defmodule Tuist.Repo.Migrations.AddAppCredentialsToGithubAppInstallations do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  def change do
    alter table(:github_app_installations) do
      add :app_id, :string
      add :app_slug, :string
      add :client_id, :string
      add :client_secret, :binary
      add :private_key, :binary
      add :webhook_secret, :binary
      modify :installation_id, :string, null: true
    end
  end
end
