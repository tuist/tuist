defmodule Tuist.Slack.Workers.ReportWorker do
  @moduledoc """
  An hourly job that sends scheduled Slack reports for projects.
  """
  use Oban.Worker, max_attempts: 3

  import Ecto.Query

  alias Tuist.Projects.Project
  alias Tuist.Repo
  alias Tuist.Slack.Client, as: SlackClient
  alias Tuist.Slack.Reports

  @impl Oban.Worker
  def perform(_job) do
    now = DateTime.utc_now()
    current_hour = now.hour
    current_day_of_week = Date.day_of_week(DateTime.to_date(now))

    projects = list_projects_with_due_reports(current_hour, current_day_of_week)

    for project <- projects do
      send_report(project)
    end

    :ok
  end

  defp list_projects_with_due_reports(current_hour, current_day_of_week) do
    Repo.all(
      from(p in Project,
        where: p.slack_report_enabled == true,
        where: not is_nil(p.slack_channel_id),
        where: fragment("EXTRACT(HOUR FROM ?) = ?", p.slack_report_schedule_time, ^current_hour),
        where: ^current_day_of_week in p.slack_report_days_of_week,
        preload: [account: :slack_installation]
      )
    )
  end

  defp send_report(project) do
    slack_installation = project.account.slack_installation

    if slack_installation do
      report = Reports.generate_report(project, project.slack_report_frequency)
      blocks = Reports.format_report_blocks(report)
      SlackClient.post_message(slack_installation.access_token, project.slack_channel_id, blocks)
    end
  end
end
