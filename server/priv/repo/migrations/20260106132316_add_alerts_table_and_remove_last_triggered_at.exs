defmodule Tuist.Repo.Migrations.AddAlertsTableAndRemoveLastTriggeredAt do
  use Ecto.Migration

  def change do
    create table(:alerts, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :alert_rule_id, references(:alert_rules, type: :uuid, on_delete: :delete_all),
        null: false

      add :current_value, :float, null: false
      add :previous_value, :float, null: false

      timestamps(type: :timestamptz)
    end

    create index(:alerts, [:alert_rule_id])
    create index(:alerts, [:inserted_at])

    alter table(:alert_rules) do
      remove :last_triggered_at, :timestamptz
    end
  end
end
