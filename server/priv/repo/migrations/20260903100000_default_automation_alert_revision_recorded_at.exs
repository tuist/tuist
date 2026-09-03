defmodule Tuist.Repo.Migrations.DefaultAutomationAlertRevisionRecordedAt do
  use Ecto.Migration

  def up do
    alter table(:automation_alert_revisions) do
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify :recorded_at, :timestamptz, default: fragment("now()")
    end
  end

  def down do
    alter table(:automation_alert_revisions) do
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify :recorded_at, :timestamptz, default: nil
    end
  end
end
