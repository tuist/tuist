defmodule Tuist.Repo.Migrations.RenameSlackReportColumnsToReport do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  def change do
    rename table(:projects), :slack_report_frequency, to: :report_frequency
    rename table(:projects), :slack_report_days_of_week, to: :report_days_of_week
    rename table(:projects), :slack_report_schedule_time, to: :report_schedule_time
    rename table(:projects), :slack_report_timezone, to: :report_timezone
  end
end
