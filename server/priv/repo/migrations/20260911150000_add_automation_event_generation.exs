defmodule Tuist.Repo.Migrations.AddAutomationEventGeneration do
  use Ecto.Migration

  def change do
    alter table(:automation_alerts) do
      add :event_generation, :integer
    end
  end
end
