defmodule Tuist.Repo.Migrations.AddApiUrlToGithubAppInstallations do
  use Ecto.Migration

  def change do
    alter table(:github_app_installations) do
      add :api_url, :text
    end
  end
end
