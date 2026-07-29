defmodule Tuist.Repo.Migrations.AddLastScopedEvaluationInsertedAtToAutomationAlerts do
  use Ecto.Migration

  def change do
    alter table(:automation_alerts) do
      add :last_scoped_evaluation_inserted_at, :timestamptz
    end
  end
end
