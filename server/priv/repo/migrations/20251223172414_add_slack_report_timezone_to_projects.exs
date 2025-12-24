defmodule Tuist.Repo.Migrations.AddSlackReportTimezoneToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :slack_report_timezone, :string
    end
  end
end
