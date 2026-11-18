defmodule Tuist.Repo.Migrations.AddPlatformToSandboxAgentSessions do
  use Ecto.Migration

  def change do
    alter table(:sandbox_agent_sessions) do
      # The OS the session's sandbox runs; nil runs the environment's platform.
      add :platform, :string
    end
  end
end
