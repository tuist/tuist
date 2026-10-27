defmodule Tuist.Repo.Migrations.AddRelayMetadataToRunnerInteractiveSessions do
  use Ecto.Migration

  def change do
    alter table(:runner_interactive_sessions) do
      add :relay_host, :string
      add :relay_port, :integer
      add :relay_ready_at, :timestamptz
    end
  end
end
