defmodule Tuist.Repo.Migrations.AddFlakyTestAlertRulesTable do
  use Ecto.Migration

  def change do
    create table(:flaky_test_alert_rules, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :name, :string, null: false, default: "Untitled"
      add :trigger_threshold, :integer, null: false
      add :slack_channel_id, :string
      add :slack_channel_name, :string

      timestamps(type: :timestamptz)
    end

    create index(:flaky_test_alert_rules, [:project_id])

    create table(:flaky_test_alerts, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :flaky_test_alert_rule_id,
          references(:flaky_test_alert_rules, type: :uuid, on_delete: :delete_all),
          null: false

      add :flaky_runs_count, :integer, null: false

      timestamps(type: :timestamptz)
    end

    create index(:flaky_test_alerts, [:flaky_test_alert_rule_id])
    create index(:flaky_test_alerts, [:inserted_at])
  end
end
