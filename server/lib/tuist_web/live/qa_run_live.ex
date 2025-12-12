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
        %{"qa_run_id" => qa_run_id, "account_handle" => account_handle, "project_handle" => project_handle} = _params,
        _session,
        %{assigns: %{selected_account: selected_account}} = socket
      ) do
    case QA.qa_run(qa_run_id,
           preload: [
             run_steps: :screenshot,
             recording: [],
             app_build: [preview: [project: [:account, :vcs_connection]]]
           ]
         ) do
      {:error, :not_found} ->
        raise NotFoundError, dgettext("dashboard_qa", "QA run not found")

      {:ok, qa_run} ->
        if qa_run.app_build.preview.project.account.name != account_handle or
             qa_run.app_build.preview.project.name != project_handle do
          raise NotFoundError, dgettext("dashboard_qa", "QA run not found")
        end

        {video_url, video_duration} =
          if qa_run.recording do
            video_key =
              QA.recording_storage_key(%{
                account_handle: account_handle,
                project_handle: project_handle,
                qa_run_id: qa_run_id
              })

            {Storage.generate_download_url(video_key, selected_account, expires_in: 3600),
             qa_run.recording.duration / 1000.0}
          else
            {nil, 0}
          end

        steps = steps_with_times(qa_run)

        {:ok,
         socket
         |> assign(:qa_run, qa_run)
         |> assign(:pr_comment_url, build_pr_comment_url(qa_run))
         |> assign(:pr_number, extract_pr_number(qa_run))
         |> assign(:issues, extract_issues(qa_run.run_steps))
         |> assign(
           :head_title,
           "#{dgettext("dashboard_qa", "QA Run")} · #{qa_run.app_build.preview.project.name} · Tuist"
         )
         |> assign(:current_time, 0)
         |> assign(:duration, video_duration)
         |> assign(:video_url, video_url)
         |> assign(:steps, steps)
         |> assign(:current_step, List.first(steps))
         |> assign(:is_playing, false)
         |> assign(:playback_speed, 1.0)}
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

  defp build_pr_comment_url(%{issue_comment_id: nil}), do: nil
  defp build_pr_comment_url(%{git_ref: nil}), do: nil
  defp build_pr_comment_url(%{app_build: %{preview: %{project: %{vcs_connection: nil}}}}), do: nil

  defp build_pr_comment_url(%{
         issue_comment_id: comment_id,
         git_ref: git_ref,
         app_build: %{preview: %{project: %{vcs_connection: %{provider: :github, repository_full_handle: repo_handle}}}}
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
  def handle_event("seek", %{"time" => time}, %{assigns: %{steps: steps}} = socket) do
    current_step = find_current_step(steps, time)

    socket =
      socket
      |> assign(:current_time, time)
      |> assign(:current_step, current_step)
      |> push_event("seek-video", %{time: time, id: "qa-recording"})

    {:noreply, socket}
  end

  @impl true
  def handle_event("seek_to_step", %{"step-index" => step_index} = params, %{assigns: %{steps: steps}} = socket) do
    step = Enum.at(steps, String.to_integer(step_index))

    socket =
      socket
      |> assign(:current_time, step.time)
      |> assign(:current_step, step)
      |> push_event("seek-video", %{time: step.time, id: "qa-recording", auto_scroll: true})
      |> then(
        &if is_nil(params["scroll-to-element"]),
          do: &1,
          else: push_event(&1, "scroll-to-element", %{id: params["scroll-to-element"]})
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event("video_time_update", %{"current_time" => current_time}, %{assigns: %{steps: steps}} = socket) do
    current_step = find_current_step(steps, current_time)

    socket =
      socket
      |> assign(:current_time, current_time)
      |> assign(:current_step, current_step)

    {:noreply, socket}
  end

  @impl true
  def handle_event("video_play", _params, socket) do
    socket = assign(socket, :is_playing, true)

    {:noreply, socket}
  end

  @impl true
  def handle_event("video_pause", _params, socket) do
    socket = assign(socket, :is_playing, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("video_ended", _params, socket) do
    socket = assign(socket, :is_playing, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("change_playback_speed", %{"speed" => speed}, socket) do
    speed = String.to_float(speed)

    socket =
      socket
      |> assign(:playback_speed, speed)
      |> push_event("set-playback-speed", %{speed: speed, id: "qa-recording"})

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "seek_previous_step",
        _params,
        %{assigns: %{current_step: current_step, steps: steps, current_time: current_time}} = socket
      ) do
    step_to_seek =
      if current_time - current_step.time > 1.0 do
        current_step
      else
        Enum.at(steps, max(current_step.index - 1, 0))
      end

    socket =
      push_event(socket, "seek-video", %{
        time: step_to_seek.time,
        id: "qa-recording",
        auto_scroll: true
      })

    {:noreply, socket}
  end

  @impl true
  def handle_event("seek_next_step", _params, %{assigns: %{current_step: current_step, steps: steps}} = socket) do
    next_step = Enum.at(steps, min(current_step.index + 1, length(steps) - 1))

    socket =
      push_event(socket, "seek-video", %{
        time: next_step.time,
        id: "qa-recording",
        auto_scroll: true
      })

    {:noreply, socket}
  end

  defp find_current_step(steps, current_time) do
    steps
    |> Enum.filter(fn step ->
      step_time = if step.started_time, do: step.started_time, else: step.time
      step_time <= current_time
    end)
    |> List.last()
  end

  def format_time(seconds) do
    total_seconds = trunc(seconds)
    mins = div(total_seconds, 60)
    secs = rem(total_seconds, 60)
    "#{mins}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end

  defp format_playback_speed(speed) do
    if speed == trunc(speed) do
      "#{trunc(speed)}x"
    else
      "#{speed}x"
    end
  end

  defp steps_with_times(%{recording: nil} = _qa_run), do: []

  defp steps_with_times(
         %{run_steps: run_steps, recording: %{started_at: recording_started_at, duration: duration}} = _qa_run
       )
       when not is_nil(recording_started_at) do
    run_steps
    |> Enum.sort_by(& &1.inserted_at, DateTime)
    |> Enum.with_index()
    |> Enum.map(fn {step, index} ->
      time_seconds =
        if index == 0 do
          0
        else
          calculate_time_in_seconds(step.inserted_at, recording_started_at, duration)
        end

      started_time_seconds =
        if step.started_at do
          calculate_time_in_seconds(step.started_at, recording_started_at, duration)
        end

      step
      |> Map.put(:time, time_seconds)
      |> Map.put(:started_time, started_time_seconds)
      |> Map.put(:index, index)
    end)
  end

  defp calculate_time_in_seconds(datetime, recording_started_at, duration) do
    max(
      min(
        DateTime.diff(datetime, recording_started_at, :millisecond),
        duration
      ) / 1000.0,
      0
    )
  end
end
