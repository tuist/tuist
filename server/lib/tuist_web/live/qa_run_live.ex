defmodule TuistWeb.QARunLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Previews.PlatformTag

  alias Tuist.AppBuilds.Preview
  alias Tuist.Markdown
  alias Tuist.QA
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Utilities.SHA

  @impl true
  def mount(
        %{"qa_run_id" => qa_run_id, "account_handle" => account_handle, "project_handle" => project_handle},
        _session,
        socket
      ) do
    case QA.qa_run(qa_run_id, preload: [run_steps: :screenshot, app_build: [preview: [project: :account]]]) do
      {:error, :not_found} ->
        raise NotFoundError, gettext("QA run not found")

      {:ok, qa_run} ->
        if qa_run.app_build.preview.project.account.name != account_handle or
             qa_run.app_build.preview.project.name != project_handle do
          raise NotFoundError, gettext("QA run not found")
        end

        {:ok,
         socket
         |> assign(:qa_run, qa_run)
         |> assign(:duration, calculate_duration(qa_run))
         |> assign(:pr_comment_url, build_pr_comment_url(qa_run))
         |> assign(:pr_number, extract_pr_number(qa_run))
         |> assign(:issues, extract_issues(qa_run.run_steps))
         |> assign(:head_title, "#{gettext("QA Run")} · #{qa_run.app_build.preview.project.name} · Tuist")}
    end
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    socket = maybe_load_logs(socket, socket.assigns.live_action)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:qa_log_created, log}, socket) do
    if socket.assigns.live_action == :logs do
      current_logs = socket.assigns[:logs] || []
      log = %{log | inserted_at: NaiveDateTime.utc_now()}
      updated_logs = current_logs ++ [log]
      updated_formatted_logs = QA.prepare_and_format_logs(updated_logs, hide_usage_logs: true)

      {:noreply,
       socket
       |> assign(:logs, updated_logs)
       |> assign(:formatted_logs, updated_formatted_logs)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_event, socket) do
    {:noreply, socket}
  end

  defp calculate_duration(%{inserted_at: start_time, updated_at: end_time}) do
    case DateTime.diff(end_time, start_time, :second) do
      0 -> "< 1s"
      seconds when seconds < 60 -> "#{seconds}s"
      seconds when seconds < 3600 -> "#{div(seconds, 60)}m #{rem(seconds, 60)}s"
      seconds -> "#{div(seconds, 3600)}h #{div(rem(seconds, 3600), 60)}m"
    end
  end

  defp build_pr_comment_url(%{issue_comment_id: nil}), do: nil
  defp build_pr_comment_url(%{vcs_repository_full_handle: nil}), do: nil
  defp build_pr_comment_url(%{git_ref: nil}), do: nil

  defp build_pr_comment_url(%{
         issue_comment_id: comment_id,
         vcs_repository_full_handle: repo_handle,
         vcs_provider: :github,
         git_ref: git_ref
       })
       when is_integer(comment_id) do
    case extract_pr_number_from_git_ref(git_ref) do
      {:ok, pr_number} -> "https://github.com/#{repo_handle}/pull/#{pr_number}#issuecomment-#{comment_id}"
      :error -> nil
    end
  end

  defp build_pr_comment_url(_), do: nil

  defp extract_pr_number(%{git_ref: git_ref}) do
    case extract_pr_number_from_git_ref(git_ref) do
      {:ok, pr_number} -> pr_number
      :error -> nil
    end
  end

  defp extract_pr_number_from_git_ref(nil), do: :error

  defp extract_pr_number_from_git_ref(git_ref) do
    if String.starts_with?(git_ref, "refs/pull/") do
      [pr_number, _merge] = git_ref |> String.split("/") |> Enum.take(-2)
      {:ok, pr_number}
    else
      :error
    end
  end

  defp extract_issues(run_steps) do
    run_steps
    |> Enum.flat_map(fn step ->
      Enum.map(step.issues, fn issue ->
        %{
          issue: issue,
          step: step,
          screenshot: step.screenshot
        }
      end)
    end)
    |> Enum.with_index(1)
  end

  defp format_commit_sha(sha), do: SHA.format_commit_sha(sha)

  defp maybe_load_logs(socket, :logs) do
    qa_run_id = socket.assigns.qa_run.id

    logs = QA.logs_for_run(qa_run_id)
    formatted_logs = QA.prepare_and_format_logs(logs, hide_usage_logs: true)

    if connected?(socket) do
      Tuist.PubSub.subscribe("qa_logs:#{qa_run_id}")
    end

    socket
    |> assign(:logs, logs)
    |> assign(:formatted_logs, formatted_logs)
  end

  defp maybe_load_logs(socket, _action), do: socket
end
