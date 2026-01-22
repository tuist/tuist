defmodule Tuist.Repo.Migrations.AddAutomationFieldsToProjects do
  use Ecto.Migration

  # Adding columns with defaults is safe on PostgreSQL 11+ (non-blocking)
  def change do
    alter table(:projects) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :auto_quarantine_flaky_tests, :boolean, default: true
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :flaky_test_alerts_enabled, :boolean, default: false
      add :flaky_test_alerts_slack_channel_id, :string
      add :flaky_test_alerts_slack_channel_name, :string
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :auto_mark_flaky_tests, :boolean, default: true
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :auto_mark_flaky_threshold, :integer, default: 1
    end
  end
end
