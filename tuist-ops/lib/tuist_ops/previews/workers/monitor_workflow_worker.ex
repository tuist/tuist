defmodule TuistOps.Previews.Workers.MonitorWorkflowWorker do
  @moduledoc """
  Polls the GitHub Actions preview deploy run and updates the Slack card when it
  reaches a terminal state.
  """

  use Oban.Worker,
    queue: :preview_monitor,
    unique: [
      period: :infinity,
      fields: [:args],
      keys: [:preview_id, :run_name],
      states: Oban.Job.states() -- [:completed, :discarded, :cancelled]
    ],
    max_attempts: 240

  alias TuistOps.JIT.SlackClient
  alias TuistOps.Previews.GitHubActionsClient
  alias TuistOps.Previews.Preview
  alias TuistOps.Previews.SlackBlocks
  alias TuistOps.Repo

  @poll_interval_seconds 30

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"preview_id" => preview_id, "run_name" => run_name}}) do
    case Repo.get(Preview, preview_id) do
      nil ->
        :ok

      %Preview{workflow_run_name: ^run_name, status: "creating"} = preview ->
        monitor(preview)

      %Preview{} ->
        :ok
    end
  end

  defp monitor(%Preview{workflow_run_name: run_name} = preview) do
    case GitHubActionsClient.workflow_run(run_name) do
      {:ok, %{status: "completed", conclusion: "success"} = run} ->
        mark_deployed(preview, run)

      {:ok, %{status: "completed"} = run} ->
        mark_failed(preview, run)

      {:ok, _run} ->
        {:snooze, @poll_interval_seconds}

      {:error, :not_found} ->
        {:snooze, @poll_interval_seconds}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp mark_deployed(%Preview{} = preview, run) do
    workflow_run_url = run[:html_url]
    slack_preview = %{preview | workflow_run_url: workflow_run_url}

    :ok =
      SlackClient.update_message(
        preview.slack_channel_id,
        preview.slack_message_ts,
        SlackBlocks.deployed(slack_preview),
        fallback_text: "Preview deployed"
      )

    preview
    |> Preview.transition_changeset(%{
      status: "active",
      workflow_run_url: workflow_run_url
    })
    |> Repo.update()
    |> case do
      {:ok, _preview} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp mark_failed(%Preview{} = preview, run) do
    reason = {:workflow_failed, run[:conclusion] || "unknown"}
    workflow_run_url = run[:html_url]
    slack_preview = %{preview | workflow_run_url: workflow_run_url}

    :ok =
      SlackClient.update_message(
        preview.slack_channel_id,
        preview.slack_message_ts,
        SlackBlocks.failed(slack_preview, reason),
        fallback_text: "Preview request failed"
      )

    preview
    |> Preview.transition_changeset(%{
      status: "failed",
      failed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      failure_reason: inspect(reason),
      workflow_run_url: workflow_run_url
    })
    |> Repo.update()
    |> case do
      {:ok, _preview} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end
end
