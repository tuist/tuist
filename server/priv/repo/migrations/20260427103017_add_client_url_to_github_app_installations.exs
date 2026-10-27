defmodule Tuist.Repo.Migrations.AddClientUrlToGithubAppInstallations do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  def change do
    alter table(:github_app_installations) do
      add :client_url, :string, null: false, default: "https://github.com"
    end
  end
end
