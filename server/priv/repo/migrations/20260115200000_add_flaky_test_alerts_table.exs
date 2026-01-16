defmodule Tuist.Repo.Migrations.AddFlakyTestAlertsTable do
  use Ecto.Migration

  def change do
    create table(:flaky_test_alerts, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :flaky_test_alert_rule_id,
          references(:flaky_test_alert_rules, type: :uuid, on_delete: :delete_all),
          null: false

      add :flaky_runs_count, :integer, null: false
      add :test_case_id, :uuid
      add :test_case_name, :string
      add :test_case_module_name, :string
      add :test_case_suite_name, :string

      timestamps(type: :timestamptz)
    end

    create index(:flaky_test_alerts, [:flaky_test_alert_rule_id])
    create index(:flaky_test_alerts, [:inserted_at])
  end
end
