defmodule Tuist.Repo.Migrations.AddXcodeVersionToSandboxAgents do
  use Ecto.Migration

  # The Xcode a macOS agent environment's sandboxes boot, and the one a
  # session asked for instead. Null is the default Xcode (the environment's,
  # for a session). See Tuist.Sandboxes.Xcode.
  def change do
    alter table(:sandbox_agent_environments) do
      add :xcode_version, :string
    end

    alter table(:sandbox_agent_sessions) do
      add :xcode_version, :string
    end
  end
end
