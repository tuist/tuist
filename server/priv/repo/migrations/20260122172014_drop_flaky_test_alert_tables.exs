defmodule Tuist.Repo.Migrations.DropFlakyTestAlertTables do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  def up do
    # excellent_migrations:safety-assured-for-next-line table_dropped
    drop table(:flaky_test_alerts)
    # excellent_migrations:safety-assured-for-next-line table_dropped
    drop table(:flaky_test_alert_rules)
  end

  def down do
    create table(:flaky_test_alert_rules, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :trigger_threshold, :integer, null: false
      add :slack_channel_id, :string
      add :slack_channel_name, :string
      timestamps(type: :timestamptz)
    end

    create index(:flaky_test_alert_rules, [:project_id])

    create table(:flaky_test_alerts, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :flaky_test_alert_rule_id,
          references(:flaky_test_alert_rules, type: :uuid, on_delete: :delete_all),
          null: false

      add :flaky_runs_count, :integer, null: false
      add :test_case_id, :uuid
      add :test_case_name, :string
      add :test_case_module_name, :string
      add :test_case_suite_name, :string
      timestamps(type: :timestamptz, updated_at: false)
    end

    create index(:flaky_test_alerts, [:flaky_test_alert_rule_id])
  end
end
