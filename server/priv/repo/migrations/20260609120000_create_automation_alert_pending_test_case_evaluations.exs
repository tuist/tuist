defmodule Tuist.Repo.Migrations.CreateAutomationAlertPendingTestCaseEvaluations do
  use Ecto.Migration

  def change do
    create table(:automation_alert_pending_test_case_evaluations, primary_key: false) do
      add :alert_id, references(:automation_alerts, type: :uuid, on_delete: :delete_all),
        null: false

      add :test_case_id, :uuid, null: false
      add :generation, :bigint, null: false, default: 1

      timestamps(type: :timestamptz, updated_at: false)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(
             :automation_alert_pending_test_case_evaluations,
             [:alert_id, :test_case_id],
             name: :automation_alert_pending_test_case_evaluations_alert_case_index
           )
  end
end
