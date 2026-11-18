defmodule Tuist.Repo.Migrations.AddExecutionIdentityToRunnerSessions do
  use Ecto.Migration

  def change do
    alter table(:runner_sessions) do
      add :execution_identity, :map
    end

    alter table(:runner_gitlab_jobs) do
      add :cache_volume_identity, :map
    end
  end
end
