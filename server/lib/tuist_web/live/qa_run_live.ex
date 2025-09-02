defmodule TuistWeb.QARunLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Previews.PlatformTag

  alias Tuist.AppBuilds.Preview
  alias Tuist.QA
  alias Tuist.Storage
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Utilities.SHA

  @impl true
  def mount(
        %{
          "qa_run_id" => qa_run_id,
          "account_handle" => account_handle,
          "project_handle" => project_handle
        } = params,
        _session,
        %{assigns: %{selected_account: selected_account}} = socket
      ) do
    case QA.qa_run(qa_run_id,
           preload: [run_steps: :screenshot, app_build: [preview: [project: :account]]]
         ) do
      {:error, :not_found} ->
        raise NotFoundError, gettext("QA run not found")

      {:ok, qa_run} ->
        if qa_run.app_build.preview.project.account.name != account_handle or
             qa_run.app_build.preview.project.name != project_handle do
          raise NotFoundError, gettext("QA run not found")
        end

        tab = Map.get(params, "tab", "overview")

        agent_actions = [
          %{
            time: 5,
            type: "click",
            description: "Click login button",
            screenshot: "/images/screenshot_1.png"
          },
          %{
            time: 8,
            type: "input",
            description: "Enter username",
            screenshot: "/images/screenshot_2.png"
          },
          %{
            time: 12,
            type: "input",
            description: "Enter password",
            screenshot: "/images/screenshot_3.png"
          },
          %{
            time: 15,
            type: "click",
            description: "Submit form",
            screenshot: "/images/screenshot_4.png"
          },
          %{
            time: 22,
            type: "wait",
            description: "Wait for page load",
            screenshot: "/images/screenshot_5.png"
          },
          %{
            time: 28,
            type: "assertion",
            description: "Verify dashboard loaded",
            screenshot: "/images/screenshot_6.png"
          },
          %{
            time: 35,
            type: "click",
            description: "Navigate to settings",
            screenshot: "/images/screenshot_7.png"
          },
          %{
            time: 42,
            type: "scroll",
            description: "Scroll to bottom",
            screenshot: "/images/screenshot_8.png"
          },
          %{
            time: 48,
            type: "click",
            description: "Toggle dark mode",
            screenshot: "/images/screenshot_9.png"
          },
          %{
            time: 55,
            type: "assertion",
            description: "Verify theme changed",
            screenshot: "/images/screenshot_10.png"
          },
          %{
            time: 65,
            type: "click",
            description: "Open user menu",
            screenshot: "/images/screenshot_11.png"
          },
          %{
            time: 72,
            type: "click",
            description: "Logout",
            screenshot: "/images/screenshot_12.png"
          },
          %{
            time: 78,
            type: "assertion",
            description: "Verify logout success",
            screenshot: "/images/screenshot_13.png"
          }
        ]

        # Generate presigned URL for the video
        video_key = "qa/test.mp4"
        video_exists = Storage.object_exists?(video_key, selected_account)

        video_url =
          if video_exists do
            Storage.generate_download_url(video_key, selected_account, expires_in: 3600)
          end

        {:ok,
         socket
         |> assign(:qa_run, qa_run)
         |> assign(:selected_tab, tab)
         |> assign(:duration, calculate_duration(qa_run))
         |> assign(:pr_comment_url, build_pr_comment_url(qa_run))
         |> assign(:pr_number, extract_pr_number(qa_run))
         |> assign(:issues, extract_issues(qa_run.run_steps))
         |> assign(
           :head_title,
           "#{gettext("QA Run")} · #{qa_run.app_build.preview.project.name} · Tuist"
         )
         |> assign(:agent_actions, agent_actions)
         |> assign(:current_time, 0)
         |> assign(:duration, 0)
         |> assign(:is_playing, false)
         |> assign(:current_action, nil)
         |> assign(:video_url, video_url)
         |> assign(:video_exists, video_exists)}
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
  defp build_pr_comment_url(%{git_ref: nil}), do: nil

  defp build_pr_comment_url(%{
         issue_comment_id: comment_id,
         vcs_repository_full_handle: repo_handle,
         vcs_provider: :github,
         git_ref: git_ref
       })
       when is_integer(comment_id) do
    case extract_pr_number_from_git_ref(git_ref) do
      {:ok, pr_number} ->
        "https://github.com/#{repo_handle}/pull/#{pr_number}#issuecomment-#{comment_id}"

      :error ->
        nil
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

  @impl true
  def handle_event("play_pause", _params, socket) do
    is_playing = !socket.assigns.is_playing

    socket =
      socket
      |> assign(:is_playing, is_playing)
      |> then(
        &if &1.assigns.is_playing,
          do: push_event(&1, "play-video", %{id: "qa-recording"}),
          else: push_event(&1, "pause-video", %{id: "qa-recording"})
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event("reset", _params, socket) do
    socket =
      socket
      |> assign(:current_time, 0)
      |> assign(:is_playing, false)
      |> assign(:current_action, nil)
      |> push_event("seek_video", %{time: 0})

    {:noreply, socket}
  end

  @impl true
  def handle_event("seek", %{"time" => time_str}, socket) do
    {time, _} = Float.parse(time_str)
    current_action = find_current_action(socket.assigns.agent_actions, time)

    socket =
      socket
      |> assign(:current_time, time)
      |> assign(:current_action, current_action)
      |> assign(:is_playing, false)
      |> push_event("seek-video", %{time: time, id: "qa-recording"})

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "video_time_update",
        %{"current_time" => current_time, "duration" => duration},
        socket
      ) do
    current_action = find_current_action(socket.assigns.agent_actions, current_time)

    socket =
      socket
      |> assign(:current_time, current_time)
      |> assign(:current_action, current_action)
      |> assign(:duration, duration)

    {:noreply, socket}
  end

  @impl true
  def handle_event("video_metadata", %{"duration" => duration}, socket) do
    {:noreply, assign(socket, :duration, duration)}
  end

  @impl true
  def handle_event("video_ended", _params, socket) do
    {:noreply, assign(socket, :is_playing, false)}
  end

  defp find_current_action(actions, current_time) do
    Enum.find(actions, fn action ->
      abs(action.time - current_time) < 2 && action.time <= current_time
    end)
  end

  defp format_time(seconds) do
    total_seconds = trunc(seconds)
    mins = div(total_seconds, 60)
    secs = rem(total_seconds, 60)
    "#{mins}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end

  defp timeline_progress(_current_time, 0), do: 0

  defp timeline_progress(current_time, duration) do
    dbg(current_time / duration * 100)
  end

  defp action_color(type) do
    case type do
      "click" -> "action-click"
      "input" -> "action-input"
      "wait" -> "action-wait"
      "assertion" -> "action-assertion"
      "scroll" -> "action-scroll"
      _ -> "action-default"
    end
  end

  defp action_icon(type) do
    case type do
      "click" -> "👆"
      "input" -> "⌨️"
      "wait" -> "⏳"
      "assertion" -> "✓"
      "scroll" -> "📜"
      _ -> "•"
    end
  end

  defp generate_time_markers(duration) when duration <= 0, do: [0]

  defp generate_time_markers(duration) do
    markers =
      cond do
        duration <= 10 -> [0, 5, 10]
        duration <= 30 -> [0, 15, 30]
        duration <= 60 -> [0, 15, 30, 45, 60]
        duration <= 120 -> [0, 30, 60, 90, 120]
        duration <= 300 -> Enum.take_every(0..trunc(duration), 60)
        duration <= 600 -> Enum.take_every(0..trunc(duration), 120)
        true -> Enum.take_every(0..trunc(duration), 300)
      end

    # Only show markers that are within the actual video duration
    Enum.filter(markers, &(&1 <= duration))
  end
end
