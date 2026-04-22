defmodule Tuist.Repo.Migrations.DropLegacyFlakyColumnsFromProjects do
  use Ecto.Migration

  # The Automations engine (introduced in the preceding PR) fully replaces the
  # project-level flaky flags. The backfill migration already copied the
  # relevant per-project settings into automation alerts, and no production
  # code still reads these columns.
  #
  # excellent_migrations:safety-assured-for-next-line column_removed
  def up do
    alter table(:projects) do
      remove :auto_mark_flaky_tests
      remove :auto_mark_flaky_threshold
      remove :auto_quarantine_flaky_tests
      remove :flaky_cooldown_days
      remove :flaky_test_alerts_enabled
      remove :flaky_test_alerts_slack_channel_id
      remove :flaky_test_alerts_slack_channel_name
    end
  end

  def down do
    alter table(:projects) do
      add :auto_mark_flaky_tests, :boolean, default: true
      add :auto_mark_flaky_threshold, :integer, default: 1
      add :auto_quarantine_flaky_tests, :boolean, default: false
      add :flaky_cooldown_days, :integer, default: 14
      add :flaky_test_alerts_enabled, :boolean, default: false
      add :flaky_test_alerts_slack_channel_id, :string
      add :flaky_test_alerts_slack_channel_name, :string
    end
  end
end
