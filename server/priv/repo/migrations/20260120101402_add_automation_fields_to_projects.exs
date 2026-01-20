defmodule Tuist.Repo.Migrations.AddAutomationFieldsToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :auto_quarantine_flaky_tests, :boolean, default: true
      add :flaky_test_alerts_enabled, :boolean, default: false
      add :flaky_test_alerts_slack_channel_id, :string
      add :flaky_test_alerts_slack_channel_name, :string
      add :auto_mark_flaky_tests, :boolean, default: true
      add :auto_mark_flaky_threshold, :integer, default: 1
    end
  end
end
