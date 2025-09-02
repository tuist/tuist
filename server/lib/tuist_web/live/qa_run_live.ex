defmodule TuistWeb.QARunLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection

  alias Tuist.QA
  alias Tuist.Storage
  alias TuistWeb.Errors.NotFoundError

  @impl true
  def mount(
        %{
          "qa_run_id" => qa_run_id,
          "account_handle" => account_handle,
          "project_handle" => project_handle
        } = params,
        _session,
        socket
      ) do
    case QA.qa_run(qa_run_id,
           preload: [run_steps: :screenshot, app_build: [preview: [project: :account]]]
         ) do
      {:error, :not_found} ->
        raise NotFoundError, gettext("QA run not found")

      {:ok, qa_run} ->
        # Verify the QA run belongs to the requested project
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
        video_exists = Storage.object_exists?(video_key)
        
        video_url = if video_exists do
          Storage.generate_download_url(video_key, expires_in: 3600)
        else
          nil
        end

        {:ok,
         socket
         |> assign(:qa_run, qa_run)
         |> assign(:selected_tab, tab)
         |> assign(:duration, calculate_duration(qa_run))
         |> assign(:pr_comment_url, build_pr_comment_url(qa_run))
         |> assign(:issues, extract_issues(qa_run.run_steps))
         |> assign(
           :head_title,
           "#{gettext("QA Run")} · #{qa_run.app_build.preview.project.name} · Tuist"
         )
         |> assign(:agent_actions, agent_actions)
         |> assign(:current_time, 0)
         |> assign(:duration, 120)
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
      step.issues
      |> Enum.map(fn issue ->
        %{
          issue: issue,
          step: step,
          screenshot: step.screenshot
        }
      end)
    end)
    |> Enum.with_index(1)
  end

  defp format_datetime(%DateTime{} = datetime) do
    Timex.format!(datetime, "{WDshort} {D} {Mfull} {h24}:{m}:{s}")
  end

  defp format_datetime(_), do: gettext("Unknown")

  defp format_commit_sha(nil), do: gettext("None")

  defp format_commit_sha(sha) when is_binary(sha) do
    String.slice(sha, 0, 7)
  end

  @impl true
  def handle_event("play_pause", _params, socket) do
    is_playing = !socket.assigns.is_playing
    socket = assign(socket, :is_playing, is_playing)

    if is_playing do
      Process.send_after(self(), :update_time, 100)
    end

    socket = push_event(socket, "update_video_state", %{})

    {:noreply, socket}
  end

  @impl true
  def handle_event("reset", _params, socket) do
    socket =
      socket
      |> assign(:current_time, 0)
      |> assign(:is_playing, false)
      |> assign(:current_action, nil)
      |> push_event("update_video_state", %{})

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
      |> push_event("update_video_state", %{})

    {:noreply, socket}
  end

  @impl true
  def handle_info(:update_time, socket) do
    if socket.assigns.is_playing do
      new_time = socket.assigns.current_time + 0.1
      current_action = find_current_action(socket.assigns.agent_actions, new_time)

      socket =
        socket
        |> assign(:current_time, min(new_time, socket.assigns.duration))
        |> assign(:current_action, current_action)

      socket =
        if new_time < socket.assigns.duration do
          Process.send_after(self(), :update_time, 100)
          socket
        else
          assign(socket, :is_playing, false)
        end

      {:noreply, socket}
    else
      {:noreply, socket}
    end
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

  defp timeline_progress(current_time, duration) do
    current_time / duration * 100
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
end
