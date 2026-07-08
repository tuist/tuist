defmodule Tuist.Repo.Migrations.AddConnectionIdToRunnerInteractiveSessions do
  use Ecto.Migration

  def change do
    alter table(:runner_interactive_sessions) do
      add :connection_id, :string
    end
  end
end
