defmodule Tuist.Repo.Migrations.AddBuildRunIdToCommandEvents do
  use Ecto.Migration

  def change do
    alter table(:command_events) do
      add :build_run_id, :uuid
    end
  end
end
