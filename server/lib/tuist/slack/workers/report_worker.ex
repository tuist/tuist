defmodule Tuist.Slack.Workers.ReportWorker do
  @moduledoc """
  An hourly job that sends scheduled Slack reports for projects.

  The cron job finds projects due for reports and enqueues individual
  project-specific jobs. This allows tracking when the last report was
  sent per project via the oban_jobs table.
  """
  use Oban.Worker, max_attempts: 3

  import Ecto.Query

  alias Tuist.Projects
  alias Tuist.Projects.Project
  alias Tuist.Repo
  alias Tuist.Slack.Client, as: SlackClient
  alias Tuist.Slack.Reports

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id}}) do
    project = Projects.get_project_by_id(project_id)

    if project do
      project = Repo.preload(project, account: :slack_installation)
      send_report(project)
    end

    :ok
  end

  def perform(_job) do
    now = DateTime.utc_now()
    current_hour = now.hour
    current_day_of_week = Date.day_of_week(DateTime.to_date(now))

    projects = list_projects_with_due_reports(current_hour, current_day_of_week)

    for project <- projects do
      %{project_id: project.id}
      |> __MODULE__.new()
      |> Oban.insert()
    end

    :ok
  end

  defp list_projects_with_due_reports(current_hour, current_day_of_week) do
    Repo.all(
      from(p in Project,
        where: p.slack_report_enabled == true,
        where: not is_nil(p.slack_channel_id),
        where: fragment("EXTRACT(HOUR FROM ?) = ?", p.slack_report_schedule_time, ^current_hour),
        where: ^current_day_of_week in p.slack_report_days_of_week
      )
    )
  end

  defp send_report(project) do
    slack_installation = project.account.slack_installation

    if slack_installation do
      last_report_at = get_last_report_time(project.id)

      report =
        Reports.generate_report(project, project.slack_report_frequency, last_report_at: last_report_at)

      blocks = Reports.format_report_blocks(report)
      SlackClient.post_message(slack_installation.access_token, project.slack_channel_id, blocks)
    end
  end

  defp get_last_report_time(project_id) do
    worker_name = inspect(__MODULE__)
    project_id_string = to_string(project_id)

    Repo.one(
      from(j in "oban_jobs",
        where: j.worker == ^worker_name,
        where: j.state == "completed",
        where: fragment("?->>'project_id' = ?", j.args, ^project_id_string),
        order_by: [desc: j.completed_at],
        limit: 1,
        select: j.completed_at
      )
    )
    |> case do
      nil -> nil
      naive_dt -> DateTime.from_naive!(naive_dt, "Etc/UTC")
    end
  end
end
