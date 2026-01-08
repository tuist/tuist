defmodule Tuist.Repo.Migrations.AddSlackReportColumnsToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :slack_channel_id, :string
      add :slack_channel_name, :string
      add :slack_report_frequency, :integer, default: 0, null: false
      add :slack_report_days_of_week, {:array, :integer}, default: [], null: false
      add :slack_report_schedule_time, :timestamptz
      add :slack_report_timezone, :string
    end
  end
end
