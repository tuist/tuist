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
      :ok = send_report(project)
    end

    :ok
  end

  def perform(_job) do
    now = DateTime.utc_now()

    projects =
      Repo.all(
        from(p in Project,
          where: p.slack_report_frequency == :daily
        )
      )

    for project <- projects, is_due?(project, now) do
      %{project_id: project.id}
      |> __MODULE__.new(unique: [period: 3600, keys: [:project_id]])
      |> Oban.insert()
    end

    :ok
  end

  defp is_due?(project, now_utc) do
    timezone = project.slack_report_timezone
    local_now = Timex.Timezone.convert(now_utc, timezone)
    local_hour = local_now.hour
    local_day = Date.day_of_week(DateTime.to_date(local_now))

    scheduled_local_hour = get_scheduled_local_hour(project.slack_report_schedule_time, timezone)
    days_of_week = project.slack_report_days_of_week || []

    local_hour == scheduled_local_hour and local_day in days_of_week
  end

  defp get_scheduled_local_hour(utc_datetime, timezone) do
    local_datetime = Timex.Timezone.convert(utc_datetime, timezone)
    local_datetime.hour
  end

  defp send_report(project) do
    slack_installation = project.account.slack_installation

    if slack_installation && project.slack_channel_id do
      last_report_at = get_last_report_time(project.id)
      blocks = Reports.report(project, last_report_at: last_report_at)
      SlackClient.post_message(slack_installation.access_token, project.slack_channel_id, blocks)
    else
      :ok
    end
  end

  defp get_last_report_time(project_id) do
    worker_name = to_string(__MODULE__)
    project_id_string = to_string(project_id)

    from(j in "oban_jobs",
      where: j.worker == ^worker_name,
      where: j.state == "completed",
      where: fragment("?->>'project_id' = ?", j.args, ^project_id_string),
      order_by: [desc: j.completed_at],
      limit: 1,
      select: j.completed_at
    )
    |> Repo.one()
    |> case do
      nil -> nil
      naive_dt -> DateTime.from_naive!(naive_dt, "Etc/UTC")
    end
  end
end
