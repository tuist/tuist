defmodule TuistWeb.QARunLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Previews.PlatformTag

  alias Tuist.AppBuilds.Preview
  alias Tuist.Markdown
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
        } = _params,
        _session,
        %{assigns: %{selected_account: selected_account}} = socket
      ) do
    case QA.qa_run(qa_run_id,
           preload: [
             run_steps: :screenshot,
             recording: [],
             app_build: [preview: [project: :account]]
           ]
         ) do
      {:error, :not_found} ->
        raise NotFoundError, gettext("QA run not found")

      {:ok, qa_run} ->
        if qa_run.app_build.preview.project.account.name != account_handle or
             qa_run.app_build.preview.project.name != project_handle do
          raise NotFoundError, gettext("QA run not found")
        end

        # Generate presigned URL for the video recording
        video_key =
          QA.recording_storage_key(%{
            account_handle: account_handle,
            project_handle: project_handle,
            qa_run_id: qa_run_id
          })

        video_exists = Storage.object_exists?(video_key, selected_account)

        video_url =
          if video_exists do
            Storage.generate_download_url(video_key, selected_account, expires_in: 3600)
          end

        # Convert recording duration from milliseconds to seconds
        video_duration =
          if qa_run.recording && qa_run.recording.duration do
            qa_run.recording.duration / 1000.0
          else
            0
          end

        {step_positions, ordered_run_steps} = calculate_step_positions(qa_run)

        {:ok,
         socket
         |> assign(:qa_run, qa_run)
         |> assign(:duration_display, calculate_duration(qa_run))
         |> assign(:pr_comment_url, build_pr_comment_url(qa_run))
         |> assign(:pr_number, extract_pr_number(qa_run))
         |> assign(:issues, extract_issues(qa_run.run_steps))
         |> assign(
           :head_title,
           "#{gettext("QA Run")} · #{qa_run.app_build.preview.project.name} · Tuist"
         )
         |> assign(:current_time, 0)
         |> assign(:duration, video_duration)
         |> assign(:current_action, nil)
         |> assign(:video_url, video_url)
         |> assign(:video_exists, video_exists)
         |> assign(:step_positions, step_positions)
         |> assign(:ordered_run_steps, ordered_run_steps)
         |> assign(:current_step, nil)}
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
  @impl true
  def handle_event("play_pause", _params, socket) do
    socket = push_event(socket, "play-pause-toggle", %{id: "qa-recording"})

    {:noreply, socket}
  end

  @impl true
  def handle_event("reset", _params, socket) do
    socket =
      socket
      |> assign(:current_time, 0)
      |> assign(:current_action, nil)
      |> assign(:current_step, nil)
      |> push_event("seek_video", %{time: 0})

    {:noreply, socket}
  end

  @impl true
  def handle_event("seek", %{"time" => time_str}, socket) do
    {time, _} = Float.parse(time_str)
    current_step = find_current_step(socket.assigns.step_positions, time)

    socket =
      socket
      |> assign(:current_time, time)
      |> assign(:current_step, current_step)
      |> push_event("seek-video", %{time: time, id: "qa-recording"})

    {:noreply, socket}
  end

  @impl true
  def handle_event("seek_to_step", %{"step-index" => step_index_str} = params, socket) do
    step_index = String.to_integer(step_index_str)

    # Get the step position by array index (0-based)
    step_position = Enum.at(socket.assigns.step_positions, step_index)

    if step_position do
      # Use the time directly from the step
      seek_time = step_position.time
      current_step = step_position.step

      socket =
        socket
        |> assign(:current_time, seek_time)
        |> assign(:current_step, current_step)
        |> push_event("seek-video", %{time: seek_time, id: "qa-recording", auto_scroll: true})

      # Only scroll to element if scroll-to-element parameter is provided
      socket =
        case Map.get(params, "scroll-to-element") do
          element_id when is_binary(element_id) ->
            push_event(socket, "scroll-to-element", %{id: element_id})

          _ ->
            socket
        end

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "video_time_update",
        %{"current_time" => current_time, "current_step_index" => step_index},
        socket
      ) do
    current_step = get_step_by_index(socket.assigns.step_positions, step_index)

    socket =
      socket
      |> assign(:current_time, current_time)
      |> assign(:current_step, current_step)

    {:noreply, socket}
  end

  @impl true
  def handle_event("video_time_update", %{"current_time" => current_time}, socket) do
    # Fallback for when step index is not provided
    current_step = find_current_step(socket.assigns.step_positions, current_time)

    socket =
      socket
      |> assign(:current_time, current_time)
      |> assign(:current_step, current_step)

    {:noreply, socket}
  end

  @impl true
  def handle_event("video_metadata", %{"duration" => _duration}, socket) do
    # Duration is already set from the database, so we don't override it
    {:noreply, socket}
  end

  @impl true
  def handle_event("video_ended", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("seek_prev", _params, socket) do
    socket = push_event(socket, "seek-prev-step", %{})

    {:noreply, socket}
  end

  @impl true
  def handle_event("seek_next", _params, socket) do
    socket = push_event(socket, "seek-next-step", %{})

    {:noreply, socket}
  end

  defp find_current_step(step_positions, current_time) do
    # Find the step that is closest to the current time but not after it
    step_positions
    |> Enum.filter(fn step_position -> step_position.time <= current_time end)
    |> Enum.max_by(fn step_position -> step_position.time end, fn -> nil end)
    |> case do
      nil -> nil
      step_position -> step_position.step
    end
  end

  defp get_step_by_index(step_positions, step_index) when is_integer(step_index) do
    case Enum.at(step_positions, step_index) do
      nil -> nil
      step_position -> step_position.step
    end
  end

  defp get_step_by_index(_step_positions, _step_index), do: nil

  def format_time(seconds) do
    total_seconds = trunc(seconds)
    mins = div(total_seconds, 60)
    secs = rem(total_seconds, 60)
    "#{mins}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end

  defp calculate_step_positions(%{recording: nil} = _qa_run), do: {[], []}

  defp calculate_step_positions(
         %{
           run_steps: run_steps,
           recording: %{started_at: recording_started_at, duration: duration}
         } = _qa_run
       )
       when not is_nil(recording_started_at) do
    if Enum.empty?(run_steps) do
      {[], []}
    else
      ordered_run_steps = Enum.sort_by(run_steps, & &1.inserted_at, DateTime)

      step_positions =
        Enum.map(ordered_run_steps, fn step ->
          # Calculate time based on timestamp relative to recording start
          step_offset_ms =
            min(
              DateTime.diff(step.inserted_at, recording_started_at, :millisecond) + 300,
              duration
            )

          # Convert milliseconds to seconds
          time_seconds = step_offset_ms / 1000.0
          # Ensure time is not negative
          time_seconds = max(0, time_seconds)

          %{step: step, time: time_seconds}
        end)

      {step_positions, ordered_run_steps}
    end
  end
end
