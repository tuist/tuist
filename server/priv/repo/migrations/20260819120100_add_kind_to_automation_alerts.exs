defmodule Tuist.Repo.Migrations.AddKindToAutomationAlerts do
  use Ecto.Migration

  def change do
    alter table(:automation_alerts) do
      # PostgreSQL stores this constant default in table metadata without rewriting existing rows.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :kind, :string, null: false, default: "standard"
    end

    # The per-project Manual automation carries no monitor definition, so the
    # NOT NULL moves to the kind-scoped check constraint added below.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "ALTER TABLE automation_alerts ALTER COLUMN monitor_type DROP NOT NULL",
      "ALTER TABLE automation_alerts ALTER COLUMN monitor_type SET NOT NULL"
    )

    # automation_alerts is a small, low-write configuration table, so validating
    # the constraint in place cannot block application writes for long.
    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:automation_alerts, :automation_alerts_kind,
             check: "kind IN ('standard', 'manual')"
           )

    # Same small, low-write configuration table as above.
    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(
             :automation_alerts,
             :automation_alerts_standard_monitor_type,
             check: "kind = 'manual' OR monitor_type IS NOT NULL"
           )

    # A non-concurrent index build on this small, low-write configuration table
    # holds its lock only briefly.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:automation_alerts, [:project_id],
             where: "kind = 'manual'",
             name: :automation_alerts_manual_project_id_index
           )
  end
end
