defmodule Tuist.Repo.Migrations.DefaultAutomationAlertRevisionRecordedAt do
  use Ecto.Migration

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("ALTER TABLE automation_alert_revisions ALTER COLUMN recorded_at SET DEFAULT now()")
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("ALTER TABLE automation_alert_revisions ALTER COLUMN recorded_at DROP DEFAULT")
  end
end
