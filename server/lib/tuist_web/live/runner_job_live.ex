defmodule TuistWeb.RunnerJobLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Authorization
  alias Tuist.FeatureFlags
  alias Tuist.Runners.JobLogs
  alias Tuist.Runners.Jobs
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Utilities.Query

  # The Logs view loads a tail of this many lines on mount and pages
  # backwards in the same increment via "Load older logs". Live appends
  # arrive at the bottom via Pub/Sub. We never load the whole stream.
  @page_size 200

  @impl true
  def mount(
        %{"workflow_run_id" => workflow_run_id_param, "workflow_job_id" => workflow_job_id_param},
        _session,
        %{assigns: %{selected_account: selected_account, current_user: current_user}} = socket
      ) do
    if Authorization.authorize(:projects_read, current_user, selected_account) != :ok or
         not FeatureFlags.runners_enabled?(selected_account) do
      raise NotFoundError,
            dgettext("dashboard_runners", "The page you are looking for doesn't exist or has been moved.")
    end

    workflow_run_id = parse_id(workflow_run_id_param)
    workflow_job_id = parse_id(workflow_job_id_param)

    case Jobs.get_for_account(selected_account.id, workflow_job_id) do
      # Mirrors GitHub's 404 on `/actions/runs/<run>/job/<job>` when
      # `<job>` belongs to a different `<run>` — without this gate,
      # a tampered run-id in the URL would still load the right job
      # and just render a misleading breadcrumb.
      {:ok, %{workflow_run_id: ^workflow_run_id} = job} ->
        head_title =
          "#{job_title(job)} · #{dgettext("dashboard_runners", "Jobs")} · #{selected_account.name} · Tuist"

        if connected?(socket) do
          Tuist.PubSub.subscribe(JobLogs.topic(job.workflow_job_id))
        end

        log_lines = JobLogs.recent(job.workflow_job_id, @page_size)
        oldest_line = oldest_line_number(log_lines)

        {:ok,
         socket
         |> assign(:head_title, head_title)
         |> assign(:job, job)
         |> assign(:steps, steps(job))
         |> assign(:expanded_steps, MapSet.new())
         |> assign(:step_logs, %{})
         |> assign(:has_logs, log_lines != [])
         |> assign(:oldest_line, oldest_line)
         |> assign(:has_older, JobLogs.has_older?(job.workflow_job_id, oldest_line))
         |> stream(:log_lines, Enum.map(log_lines, &log_stream_item/1))}

      _ ->
        raise NotFoundError,
              dgettext("dashboard_runners", "The job you are looking for doesn't exist or has been moved.")
    end
  end

  @impl true
  def handle_params(_params, uri, socket) do
    params = Query.query_params(uri)

    {:noreply,
     socket
     |> assign(:selected_tab, params["tab"] || "overview")
     |> assign(:uri, URI.new!("?" <> URI.encode_query(params)))}
  end

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} ->
        id

      _ ->
        raise NotFoundError,
              dgettext("dashboard_runners", "The job you are looking for doesn't exist or has been moved.")
    end
  end

  defp job_title(%{workflow_name: workflow, job_name: job}) when workflow != "" and job != "", do: "#{workflow} · #{job}"

  defp job_title(%{job_name: job}) when job != "", do: job
  defp job_title(%{workflow_job_id: id}), do: "Job ##{id}"

  def header_title(job), do: job_title(job)

  def header_status(%{status: "completed", conclusion: conclusion}) do
    case conclusion do
      "success" -> :success
      "failure" -> :failure
      "cancelled" -> :warning
      "skipped" -> :warning
      _ -> :warning
    end
  end

  def header_status(%{status: "queued"}), do: :processing
  def header_status(%{status: "claimed"}), do: :processing
  def header_status(%{status: "running"}), do: :processing
  def header_status(_), do: :processing

  def status_badge_props(%{status: "completed", conclusion: "success"}),
    do: %{label: dgettext("dashboard_runners", "Passed"), color: "success"}

  def status_badge_props(%{status: "completed", conclusion: "failure"}),
    do: %{label: dgettext("dashboard_runners", "Failed"), color: "destructive"}

  def status_badge_props(%{status: "completed", conclusion: "cancelled"}),
    do: %{label: dgettext("dashboard_runners", "Cancelled"), color: "warning"}

  def status_badge_props(%{status: "completed", conclusion: "skipped"}),
    do: %{label: dgettext("dashboard_runners", "Skipped"), color: "warning"}

  def status_badge_props(%{status: "queued"}), do: %{label: dgettext("dashboard_runners", "Queued"), color: "warning"}

  def status_badge_props(%{status: "claimed"}),
    do: %{label: dgettext("dashboard_runners", "Claimed"), color: "information"}

  def status_badge_props(%{status: "running"}),
    do: %{label: dgettext("dashboard_runners", "Running"), color: "information"}

  def status_badge_props(_), do: %{label: dgettext("dashboard_runners", "Unknown"), color: "neutral"}

  def platform_label(fleet_name) when is_binary(fleet_name) do
    cond do
      String.starts_with?(fleet_name, "macos-") -> dgettext("dashboard_runners", "macOS")
      String.starts_with?(fleet_name, "linux-") -> dgettext("dashboard_runners", "Linux")
      true -> dgettext("dashboard_runners", "Unknown")
    end
  end

  def platform_label(_), do: dgettext("dashboard_runners", "Unknown")

  @doc """
  Noora badge color paired with `platform_label/1` so the Platform
  field in the CI Details card reads the same as the Platform column
  on the Jobs table — `information` (cool blue) for macOS,
  `attention` (warm yellow) for Linux.
  """
  def platform_badge_color(fleet_name) when is_binary(fleet_name) do
    cond do
      String.starts_with?(fleet_name, "macos-") -> "information"
      String.starts_with?(fleet_name, "linux-") -> "attention"
      true -> "neutral"
    end
  end

  def platform_badge_color(_), do: "neutral"

  def github_job_url(%{repository: repository, workflow_run_id: run_id, workflow_job_id: job_id})
      when is_binary(repository) and repository != "" and is_integer(run_id) and run_id > 0 and is_integer(job_id) and
             job_id > 0 do
    "https://github.com/#{repository}/actions/runs/#{run_id}/job/#{job_id}"
  end

  def github_job_url(_), do: nil

  @doc """
  Builds the deep link to a single workflow_job. Mirrors GitHub's
  `/<owner>/<repo>/actions/runs/<run_id>/job/<job_id>` shape so the
  two URLs nest the same way. Returns `nil` for rows whose
  `workflow_run_id` is missing or zero — callers can use that to
  skip the link entirely instead of routing to a broken URL.
  """
  def path(account_name, %{workflow_run_id: run_id, workflow_job_id: job_id})
      when is_binary(account_name) and is_integer(run_id) and run_id > 0 and is_integer(job_id) and job_id > 0 do
    "/#{account_name}/runners/runs/#{run_id}/jobs/#{job_id}"
  end

  def path(_, _), do: nil

  def queued_duration_ms(%{enqueued_at: enqueued, claimed_at: claimed}) do
    cond do
      is_nil(enqueued) -> 0
      is_nil(claimed) -> DateFormatter.ms_since(enqueued)
      true -> DateTime.diff(claimed, enqueued, :millisecond)
    end
  end

  def run_duration_ms(%{started_at: started, completed_at: completed}) do
    cond do
      is_nil(started) -> 0
      is_nil(completed) -> DateFormatter.ms_since(started)
      true -> DateTime.diff(completed, started, :millisecond)
    end
  end

  @doc """
  Decodes the JSON-encoded `steps` column into the list of step
  maps the template renders. Returns `[]` for jobs without captured
  steps (anything not yet completed) or on malformed JSON.
  """
  def steps(%{steps: steps}) when is_binary(steps) and steps != "" do
    case JSON.decode(steps) do
      {:ok, list} when is_list(list) -> list
      _ -> []
    end
  end

  def steps(_), do: []

  @doc """
  Maps a step's GitHub conclusion/status to the same badge kind the
  page header uses, so a step's icon reads identically to the
  job-level status indicator.
  """
  def step_status(%{"conclusion" => "success"}), do: :success
  def step_status(%{"conclusion" => "failure"}), do: :failure
  def step_status(%{"conclusion" => "cancelled"}), do: :warning
  def step_status(%{"conclusion" => "skipped"}), do: :warning
  def step_status(%{"status" => "completed"}), do: :success
  def step_status(_), do: :processing

  @doc """
  Elapsed time for a single step, in milliseconds. Returns `nil`
  when either timestamp is missing (e.g. a skipped step) so the
  template can omit the duration badge entirely.
  """
  def step_duration_ms(%{"started_at" => started, "completed_at" => completed}) do
    with {:ok, started_at} <- parse_step_time(started),
         {:ok, completed_at} <- parse_step_time(completed) do
      max(DateTime.diff(completed_at, started_at, :millisecond), 0)
    else
      _ -> nil
    end
  end

  def step_duration_ms(_), do: nil

  defp parse_step_time(value) when is_binary(value) and value != "" do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _ -> :error
    end
  end

  defp parse_step_time(_), do: :error

  @impl true
  def handle_event("toggle_step", %{"number" => number}, socket) do
    case Integer.parse(number) do
      {n, ""} ->
        expanded = socket.assigns.expanded_steps

        socket =
          if MapSet.member?(expanded, n) do
            assign(socket, :expanded_steps, MapSet.delete(expanded, n))
          else
            socket
            |> assign(:expanded_steps, MapSet.put(expanded, n))
            |> load_step_logs(n)
          end

        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("load_older", _params, %{assigns: %{oldest_line: nil}} = socket), do: {:noreply, socket}

  def handle_event("load_older", _params, socket) do
    %{job: job, oldest_line: oldest_line} = socket.assigns
    older = JobLogs.older(job.workflow_job_id, oldest_line, @page_size)

    socket =
      older
      |> Enum.reverse()
      |> Enum.reduce(socket, fn line, acc ->
        stream_insert(acc, :log_lines, log_stream_item(line), at: 0)
      end)

    new_oldest = oldest_line_number(older) || oldest_line

    {:noreply,
     socket
     |> assign(:oldest_line, new_oldest)
     |> assign(:has_older, JobLogs.has_older?(job.workflow_job_id, new_oldest))}
  end

  @impl true
  def handle_info({:runner_job_log_lines, %{lines: lines}}, socket) do
    socket =
      Enum.reduce(lines, socket, fn line, acc ->
        stream_insert(acc, :log_lines, log_stream_item(line))
      end)

    {:noreply, assign(socket, :has_logs, socket.assigns.has_logs or lines != [])}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  def step_expanded?(expanded_steps, %{"number" => number}), do: MapSet.member?(expanded_steps, number)
  def step_expanded?(_expanded_steps, _step), do: false

  @doc """
  Whether the job's logs are still being streamed in — drives the
  live "tail" affordance vs a settled, finished log.
  """
  def streaming?(%{log_state: "streaming"}), do: true
  def streaming?(%{status: status}) when status in ["queued", "claimed", "running"], do: true
  def streaming?(_), do: false

  @doc """
  Time-of-day label for a captured log line, matching the terminal
  styling of the Logs view.
  """
  def log_ts(%DateTime{} = ts), do: Calendar.strftime(ts, "%H:%M:%S")
  def log_ts(_), do: ""

  # Fetches and caches the per-step log slice the first time a step is
  # expanded. Subsequent toggles reuse the cached lines.
  defp load_step_logs(socket, number) do
    if Map.has_key?(socket.assigns.step_logs, number) do
      socket
    else
      lines = fetch_step_logs(socket.assigns.job, socket.assigns.steps, number)
      assign(socket, :step_logs, Map.put(socket.assigns.step_logs, number, lines))
    end
  end

  defp fetch_step_logs(job, steps, number) do
    with %{"started_at" => started, "completed_at" => completed} <-
           Enum.find(steps, fn step -> step["number"] == number end),
         {:ok, started_at} <- parse_step_time(started),
         {:ok, completed_at} <- parse_step_time(completed) do
      JobLogs.list_for_step(job.workflow_job_id, started_at, completed_at)
    else
      _ -> []
    end
  end

  defp log_stream_item(line) do
    %{
      id: "log-#{line.line_number}",
      line_number: line.line_number,
      ts: line.ts,
      message: line.message
    }
  end

  defp oldest_line_number([]), do: nil
  defp oldest_line_number([first | _]), do: first.line_number
end
