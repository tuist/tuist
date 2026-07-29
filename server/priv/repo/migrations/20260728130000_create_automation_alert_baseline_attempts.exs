defmodule Tuist.Repo.Migrations.CreateAutomationAlertBaselineAttempts do
  use Ecto.Migration

  def change do
    alter table(:automation_alerts) do
      # PostgreSQL stores this constant default in table metadata without rewriting existing rows.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :baseline_generation, :integer, null: false, default: 0
    end

    create table(:automation_alert_baseline_attempts, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :alert_id, references(:automation_alerts, type: :uuid, on_delete: :delete_all),
        null: false

      add :baseline_generation, :integer, null: false
      add :cursor, :timestamptz, null: false
      add :state, :string, null: false, default: "evaluating"
      add :evaluation_cursor, :map
      add :last_published_test_case_id, :uuid

      timestamps(type: :timestamptz)
    end

    # The table is created empty immediately above, so a non-concurrent index cannot block application writes.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:automation_alert_baseline_attempts, [:alert_id, :baseline_generation])

    # The table is still empty, so validating the constraint cannot scan or block existing rows.
    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(
             :automation_alert_baseline_attempts,
             :automation_alert_baseline_attempts_state,
             check: "state IN ('evaluating', 'publishing', 'committed')"
           )

    create table(:automation_alert_baseline_results, primary_key: false) do
      add :attempt_id,
          references(:automation_alert_baseline_attempts, type: :uuid, on_delete: :delete_all),
          primary_key: true,
          null: false

      add :test_case_id, :uuid, primary_key: true, null: false

      timestamps(type: :timestamptz, updated_at: false)
    end
  end
end
