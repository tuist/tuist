defmodule Tuist.Slack.Workers.ReportWorker do
  @moduledoc """
  An hourly job that sends scheduled Slack reports for projects.

  The cron job finds projects due for reports and enqueues individual
  project-specific jobs. This allows tracking when the last report was
  sent per project via the oban_jobs table.

  Reports prefer the per-channel `slack_webhook_url`. Destinations created
  before the webhook flow existed fall back to `chat.postMessage` with the
  account-level bot token.
  """
  use Oban.Worker, max_attempts: 3

  import Ecto.Query

  alias Tuist.Projects
  alias Tuist.Projects.Project
  alias Tuist.Repo
  alias Tuist.Slack
  alias Tuist.Slack.Client, as: SlackClient
  alias Tuist.Slack.Installation
  alias Tuist.Slack.Reports

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id}}) do
    case Projects.get_project_by_id(project_id) do
      nil ->
        :ok

      project ->
        project = Repo.preload(project, account: :slack_installation)
        send_report(project)
    end
  end

  def perform(_job) do
    now = DateTime.utc_now()

    projects =
      Repo.all(
        from(p in Project,
          where: p.report_frequency == :daily
        )
      )

    for project <- projects, due?(project, now) do
      %{project_id: project.id}
      |> __MODULE__.new(unique: [period: 3600, keys: [:project_id]])
      |> Oban.insert!()
    end

    :ok
  end

  defp due?(%{report_timezone: nil}, _now_utc), do: false

  defp due?(project, now_utc) do
    timezone = project.report_timezone
    local_now = Timex.Timezone.convert(now_utc, timezone)
    local_hour = local_now.hour
    local_day = Date.day_of_week(DateTime.to_date(local_now))

    scheduled_local_hour = get_scheduled_local_hour(project.report_schedule_time, timezone)
    days_of_week = project.report_days_of_week || []

    local_hour == scheduled_local_hour and local_day in days_of_week
  end

  defp get_scheduled_local_hour(utc_datetime, timezone) do
    local_datetime = Timex.Timezone.convert(utc_datetime, timezone)
    local_datetime.hour
  end

  defp send_report(project) do
    case configured_destination(project) do
      :unconfigured ->
        :ok

      {:webhook, webhook_url} ->
        last_report_at = get_last_report_time(project.id)
        blocks = Reports.report(project, last_report_at: last_report_at)

        case SlackClient.post_to_webhook(webhook_url, blocks) do
          :ok -> :ok
          {:error, reason} -> handle_webhook_error(reason, project)
        end

      {:bot_token, %Installation{access_token: token}, channel_id} ->
        last_report_at = get_last_report_time(project.id)
        blocks = Reports.report(project, last_report_at: last_report_at)

        case SlackClient.post_message(token, channel_id, blocks) do
          :ok -> :ok
          {:error, reason} -> handle_post_message_error(reason, project)
        end
    end
  end

  defp configured_destination(%Project{slack_webhook_url: url}) when is_binary(url) and url != "" do
    {:webhook, url}
  end

  defp configured_destination(%Project{
         account: %{slack_installation: %Installation{} = installation},
         slack_channel_id: channel_id
       })
       when is_binary(channel_id) do
    {:bot_token, installation, channel_id}
  end

  defp configured_destination(_), do: :unconfigured

  defp handle_webhook_error(_reason, project) do
    Logger.warning("Clearing failing Slack webhook for project #{project.id}")

    case Projects.update_project(project, %{
           slack_channel_id: nil,
           slack_channel_name: nil,
           slack_webhook_url: nil
         }) do
      {:ok, _project} -> {:discard, :webhook_failed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_post_message_error("account_inactive", project) do
    Logger.warning("Deleting inactive Slack installation for account #{project.account_id}")

    case Slack.delete_installation(project.account.slack_installation) do
      {:ok, _installation} -> {:discard, :account_inactive}
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_post_message_error("channel_not_found", project) do
    Logger.warning("Clearing missing Slack report channel for project #{project.id}")

    case Projects.update_project(project, %{slack_channel_id: nil, slack_channel_name: nil}) do
      {:ok, _project} -> {:discard, :channel_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_post_message_error(reason, _project), do: {:error, reason}

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
