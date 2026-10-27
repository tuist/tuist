defmodule Atlas.Repo.Migrations.AddAutomationExecutionAnalyticsIndex do
  use Ecto.Migration

  def change do
    create index(:automation_runs, [:inserted_at])
  end
end
