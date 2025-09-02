defmodule TuistWeb.QARunLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Previews.PlatformTag

  alias Tuist.AppBuilds.Preview
  alias Tuist.QA
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Errors.NotFoundError

  @impl true
  def mount(
        %{"qa_run_id" => qa_run_id, "account_handle" => account_handle, "project_handle" => project_handle} = params,
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

        tab = Map.get(params, "tab", "overview")

        {:ok,
         socket
         |> assign(:qa_run, qa_run)
         |> assign(:selected_tab, tab)
         |> assign(:duration, calculate_duration(qa_run))
         |> assign(:pr_comment_url, build_pr_comment_url(qa_run))
         |> assign(:issues, extract_issues(qa_run.run_steps))
         |> assign(:head_title, "#{gettext("QA Run")} · #{qa_run.app_build.preview.project.name} · Tuist")}
    end
  end

  @impl true
  def handle_params(%{"tab" => tab}, _uri, socket) do
    {:noreply, assign(socket, :selected_tab, tab)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :selected_tab, "overview")}
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

  defp build_pr_comment_url(%{
         issue_comment_id: comment_id,
         vcs_repository_full_handle: repo_handle,
         vcs_provider: :github
       })
       when is_integer(comment_id) do
    "https://github.com/#{repo_handle}/pull/#{comment_id}"
  end

  defp build_pr_comment_url(_), do: nil

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

  defp format_commit_sha(nil), do: gettext("None")

  defp format_commit_sha(sha) when is_binary(sha) do
    String.slice(sha, 0, 7)
  end
end
