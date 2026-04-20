defmodule Tuist.Repo.Migrations.CreateAutomationAlertRules do
  use Ecto.Migration

  def change do
    create table(:automation_alert_rules, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :enabled, :boolean, null: false, default: true
      add :monitor_type, :string, null: false
      add :trigger_config, :map, null: false, default: %{}
      add :cadence, :string, null: false, default: "5m"
      add :trigger_actions, {:array, :map}, null: false, default: []
      add :recovery_enabled, :boolean, null: false, default: false
      add :recovery_config, :map, null: false, default: %{}
      add :recovery_actions, {:array, :map}, null: false, default: []

      timestamps(type: :timestamptz)
    end

    create index(:automation_alert_rules, [:project_id])
  end
end
