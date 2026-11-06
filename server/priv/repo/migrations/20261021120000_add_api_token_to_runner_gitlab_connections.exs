defmodule Tuist.Repo.Migrations.AddApiTokenToRunnerGitlabConnections do
  use Ecto.Migration

  def change do
    alter table(:runner_gitlab_connections) do
      add :api_token, :binary
    end
  end
end
