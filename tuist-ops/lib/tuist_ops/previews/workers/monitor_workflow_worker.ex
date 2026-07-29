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

  require Logger

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
        preview = maybe_announce_workflow_run(preview, run)
        mark_deployed(preview, run)

      {:ok, %{status: "completed"} = run} ->
        preview = maybe_announce_workflow_run(preview, run)
        mark_failed(preview, run)

      {:ok, run} ->
        maybe_announce_workflow_run(preview, run)
        {:snooze, @poll_interval_seconds}

      {:error, :not_found} ->
        {:snooze, @poll_interval_seconds}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_announce_workflow_run(%Preview{workflow_run_url: url} = preview, _run)
       when is_binary(url) and url != "" do
    preview
  end

  defp maybe_announce_workflow_run(%Preview{} = preview, %{html_url: url})
       when is_binary(url) and url != "" do
    if is_binary(preview.slack_message_ts) do
      case SlackClient.post_message(
             preview.slack_channel_id,
             SlackBlocks.workflow_run_thread(url),
             fallback_text: "Preview deployment started",
             thread_ts: preview.slack_message_ts
           ) do
        {:ok, _thread_ts} ->
          :ok

        {:error, reason} ->
          Logger.warning("preview: workflow thread post failed: #{inspect(reason)}")
      end
    end

    preview
    |> Preview.transition_changeset(%{workflow_run_url: url})
    |> Repo.update()
    |> case do
      {:ok, preview} ->
        preview

      {:error, changeset} ->
        Logger.warning("preview: workflow run URL persist failed: #{inspect(changeset)}")
        %{preview | workflow_run_url: url}
    end
  end

  defp maybe_announce_workflow_run(%Preview{} = preview, _run), do: preview

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
      {:ok, preview} ->
        post_terminal_thread(preview, SlackBlocks.deployed_thread(preview), "Preview deployed")
        :ok

      {:error, changeset} ->
        {:error, changeset}
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
      {:ok, preview} ->
        post_terminal_thread(
          preview,
          SlackBlocks.failed_thread(preview),
          "Preview request failed"
        )

        :ok

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp post_terminal_thread(%Preview{slack_message_ts: ts} = preview, blocks, fallback_text)
       when is_binary(ts) and ts != "" do
    case SlackClient.post_message(
           preview.slack_channel_id,
           blocks,
           fallback_text: fallback_text,
           thread_ts: ts
         ) do
      {:ok, _thread_ts} ->
        :ok

      {:error, reason} ->
        Logger.warning("preview: terminal thread post failed: #{inspect(reason)}")
        :ok
    end
  end

  defp post_terminal_thread(%Preview{}, _blocks, _fallback_text), do: :ok
end
