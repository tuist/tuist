defmodule TuistWeb.RunnerJobLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.RunnerJobMetricsCharts

  alias Tuist.Authorization
  alias Tuist.FeatureFlags
  alias Tuist.Runners.Catalog
  alias Tuist.Runners.InteractiveSessions
  alias Tuist.Runners.JobLogs
  alias Tuist.Runners.JobMetrics
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.JobSteps
  alias Tuist.Runners.LogFormatter
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Utilities.Query

  # The Logs view loads a tail of this many lines on mount and pages
  # backwards in the same increment via "Load older logs". Live appends
  # arrive at the bottom via Pub/Sub. We never load the whole stream.
  @page_size 200

  # Max matching lines returned by an in-page log search (across the
  # whole job, not just the loaded tail).
  @search_limit 500

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

        log_lines = JobLogs.recent(job.workflow_job_id, @page_size)
        oldest_line = oldest_line_number(log_lines)
        machine_metrics = JobMetrics.list_for_job(job.workflow_job_id)

        # Subscribe only on the connected mount so the disconnected
        # first render doesn't open a stray subscription that gets
        # leaked when the LiveSocket connects.
        if connected?(socket), do: Tuist.PubSub.subscribe(JobLogs.topic(job.workflow_job_id))

        {:ok,
         socket
         |> assign(:head_title, head_title)
         |> assign(:job, job)
         |> assign(:interactive, interactive_state(selected_account, current_user, job))
         |> assign(:steps, JobSteps.list_for_job(job.workflow_job_id))
         |> assign(:machine_metrics, machine_metrics)
         |> assign(:expanded_steps, MapSet.new())
         |> assign(:step_logs, %{})
         |> assign(:search, "")
         |> assign(:search_results, [])
         |> assign(:show_timestamps, false)
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
    selected_tab = selected_tab(params["tab"] || "overview", socket.assigns.interactive)

    socket =
      socket
      |> assign(:selected_tab, selected_tab)
      |> assign(:uri, URI.new!("?" <> URI.encode_query(params)))
      |> maybe_auto_request_vnc_session()

    {:noreply, socket}
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
      String.starts_with?(fleet_name, Catalog.fleet_name_prefixes(:macos)) ->
        dgettext("dashboard_runners", "macOS")

      String.starts_with?(fleet_name, Catalog.fleet_name_prefixes(:linux)) ->
        dgettext("dashboard_runners", "Linux")

      true ->
        dgettext("dashboard_runners", "Unknown")
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
      String.starts_with?(fleet_name, Catalog.fleet_name_prefixes(:macos)) ->
        "information"

      String.starts_with?(fleet_name, Catalog.fleet_name_prefixes(:linux)) ->
        "attention"

      true ->
        "neutral"
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
  Maps a step's GitHub conclusion/status to the same badge kind the
  page header uses, so a step's icon reads identically to the
  job-level status indicator.
  """
  def step_status(%{conclusion: "success"}), do: :success
  def step_status(%{conclusion: "failure"}), do: :failure
  def step_status(%{conclusion: "cancelled"}), do: :warning
  def step_status(%{conclusion: "skipped"}), do: :warning
  def step_status(%{status: "completed"}), do: :success
  def step_status(_), do: :processing

  @doc """
  Elapsed time for a single step, in milliseconds. Returns `nil`
  when either timestamp is missing (e.g. a skipped step) so the
  template can omit the duration badge entirely.
  """
  def step_duration_ms(%{started_at: %DateTime{} = started, completed_at: %DateTime{} = completed}) do
    max(DateTime.diff(completed, started, :millisecond), 0)
  end

  def step_duration_ms(_), do: nil

  @doc """
  Unix-epoch milliseconds for a step boundary, or `nil` when the
  timestamp is missing. The Overview's `RunnerMetricsHighlight` hook
  reads these off the step rows to shade the matching window on the
  metrics charts when a step is hovered.
  """
  def step_epoch_ms(%DateTime{} = ts), do: DateTime.to_unix(ts, :millisecond)
  def step_epoch_ms(_), do: nil

  @doc """
  The job's step window as `%{min: start_ms, max: end_ms}` — the first
  step's start to the last step's end. The metric charts anchor their
  time axis to this so the step-hover bands line up with where the steps
  ran, rather than auto-scaling to the metric-sample extent (which
  starts before the first step during Pod boot and can end before the
  job does when the sampler run is truncated). Returns `nil` when no
  step carries timestamps.
  """
  def step_window(steps) do
    starts = steps |> Enum.map(&step_epoch_ms(&1.started_at)) |> Enum.reject(&is_nil/1)
    ends = steps |> Enum.map(&step_epoch_ms(&1.completed_at)) |> Enum.reject(&is_nil/1)

    if starts != [] and ends != [] do
      %{min: Enum.min(starts), max: Enum.max(ends)}
    end
  end

  @doc """
  Whether the job has any machine-metrics samples to chart. Drives
  the Metrics tab's empty state and gates the Overview chart row.
  """
  def has_machine_metrics?(metrics), do: metrics != []

  def interactive_tab_visible?(%{enabled?: true, can_manage?: true, macos?: true, running?: true, pod_available?: true}),
    do: true

  def interactive_tab_visible?(_), do: false

  def interactive_status_badge_props(nil), do: %{label: dgettext("dashboard_runners", "Not requested"), color: "neutral"}

  def interactive_status_badge_props(%{state: :requested}),
    do: %{label: dgettext("dashboard_runners", "Requested"), color: "information"}

  def interactive_status_badge_props(%{state: :ready}),
    do: %{label: dgettext("dashboard_runners", "Ready"), color: "success"}

  def interactive_status_badge_props(%{state: :active}),
    do: %{label: dgettext("dashboard_runners", "Connected"), color: "success"}

  def interactive_status_badge_props(%{state: :closed}),
    do: %{label: dgettext("dashboard_runners", "Closed"), color: "neutral"}

  def interactive_vnc_unavailable_reason(%{enabled?: false}),
    do: dgettext("dashboard_runners", "Interactive access is not enabled for this account.")

  def interactive_vnc_unavailable_reason(%{can_manage?: false}),
    do: dgettext("dashboard_runners", "You are not authorized to request interactive access.")

  def interactive_vnc_unavailable_reason(%{macos?: false}),
    do: dgettext("dashboard_runners", "VNC is available for macOS runner jobs.")

  def interactive_vnc_unavailable_reason(%{running?: false}),
    do: dgettext("dashboard_runners", "VNC can be requested while the macOS runner job is claimed or running.")

  def interactive_vnc_unavailable_reason(%{pod_available?: false}),
    do: dgettext("dashboard_runners", "The runner pod is not available for this job.")

  def interactive_vnc_unavailable_reason(_), do: nil

  # FetchLogsWorker finished ingesting the job's captured log. Reload
  # the tail and reset the stream so the empty state ("No logs have
  # been captured for this job yet.") flips to the loaded view without
  # the user having to refresh.
  @impl true
  def handle_info({:runner_job_logs_ready, _payload}, socket) do
    workflow_job_id = socket.assigns.job.workflow_job_id
    log_lines = JobLogs.recent(workflow_job_id, @page_size)
    oldest_line = oldest_line_number(log_lines)

    {:noreply,
     socket
     |> assign(:has_logs, log_lines != [])
     |> assign(:oldest_line, oldest_line)
     |> assign(:has_older, JobLogs.has_older?(workflow_job_id, oldest_line))
     |> stream(:log_lines, Enum.map(log_lines, &log_stream_item/1), reset: true)}
  end

  # ArchiveLogsWorker stamped `log_archived_at`. Update the assign so
  # the download button's `:if={@job.log_archived_at}` flips on.
  def handle_info({:runner_job_log_archived, %{archived_at: archived_at}}, socket) do
    {:noreply, assign(socket, :job, %{socket.assigns.job | log_archived_at: archived_at})}
  end

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

  def handle_event("search_logs", %{"search" => term}, socket) do
    term = String.trim(term)
    results = JobLogs.search(socket.assigns.job.workflow_job_id, term, @search_limit)

    {:noreply,
     socket
     |> assign(:search, term)
     |> assign(:search_results, results)}
  end

  def handle_event("toggle_timestamps", _params, socket) do
    {:noreply, assign(socket, :show_timestamps, not socket.assigns.show_timestamps)}
  end

  def handle_event("request_vnc_session", _params, socket) do
    {:noreply, request_vnc_session(socket)}
  end

  def handle_event("close_vnc_session", _params, socket) do
    %{interactive: interactive} = socket.assigns

    cond do
      not interactive.enabled? or not interactive.can_manage? ->
        {:noreply, put_flash(socket, :error, dgettext("dashboard_runners", "Interactive access is not available."))}

      is_nil(interactive.vnc_session) ->
        {:noreply, socket}

      true ->
        case InteractiveSessions.close(interactive.vnc_session, "user") do
          {:ok, _session} ->
            {:noreply,
             socket
             |> put_flash(:info, dgettext("dashboard_runners", "VNC session closed."))
             |> refresh_interactive_state()}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, dgettext("dashboard_runners", "The VNC session could not be closed."))}
        end
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

  defp request_vnc_session(socket, opts \\ []) do
    notify? = Keyword.get(opts, :notify?, true)
    %{current_user: current_user, selected_account: selected_account, job: job, interactive: interactive} = socket.assigns

    cond do
      interactive.vnc_session ->
        socket

      not interactive.enabled? or not interactive.can_manage? ->
        maybe_put_flash(socket, notify?, :error, dgettext("dashboard_runners", "Interactive access is not available."))

      not interactive.vnc_requestable? ->
        maybe_put_flash(socket, notify?, :error, interactive_vnc_unavailable_reason(interactive))

      true ->
        case InteractiveSessions.request_vnc(job, selected_account, current_user) do
          {:ok, _session} ->
            socket
            |> maybe_put_flash(notify?, :info, dgettext("dashboard_runners", "VNC session requested."))
            |> refresh_interactive_state()

          {:error, reason} ->
            maybe_put_flash(socket, notify?, :error, interactive_session_error(reason))
        end
    end
  end

  defp maybe_auto_request_vnc_session(%{assigns: %{selected_tab: "interactive"}} = socket) do
    if connected?(socket), do: request_vnc_session(socket, notify?: false), else: socket
  end

  defp maybe_auto_request_vnc_session(socket), do: socket

  defp maybe_put_flash(socket, false, _kind, _message), do: socket
  defp maybe_put_flash(socket, true, kind, nil), do: put_flash(socket, kind, interactive_session_error(nil))
  defp maybe_put_flash(socket, true, kind, message), do: put_flash(socket, kind, message)

  def step_expanded?(expanded_steps, %{number: number}), do: MapSet.member?(expanded_steps, number)
  def step_expanded?(_expanded_steps, _step), do: false

  @doc """
  Per-line timestamp label. Mirrors GitHub's "Tue, 02 Jun 2026
  20:26:29 GMT" formatting so a copied log line carries enough
  context (day-of-week, full date, UTC marker) to be useful when
  pasted into an incident channel — `12:00:42` on its own loses
  the day, which is the most common ambiguity in CI postmortems.
  """
  def log_ts(%DateTime{} = ts) do
    ts
    |> DateTime.shift_zone!("Etc/UTC")
    |> Calendar.strftime("%a, %d %b %Y %H:%M:%S GMT")
  end

  def log_ts(_), do: ""

  # Renders a list of grouped log nodes (`{:line, line}` /
  # `{:group, header, children}`) as the Steps tab body. Groups
  # become collapsible `<details>` elements that match GitHub's
  # own log UI; lines render with ANSI SGR codes decoded into
  # `<span>` classes so the user sees colours instead of literal
  # `[36;1m` artefacts.
  attr :tree, :list, required: true

  def log_tree(assigns) do
    ~H"""
    <.log_node :for={node <- @tree} node={node} />
    """
  end

  attr :node, :any, required: true

  def log_node(%{node: {:line, _line}} = assigns) do
    {:line, line} = assigns.node
    assigns = assign(assigns, :line, line)

    ~H"""
    <div data-part="log-line">
      <span data-part="log-ln">{@line.line_number}</span>
      <span data-part="log-ts">{log_ts(@line.ts)}</span>
      <span data-part="log-message">{LogFormatter.render_message(@line.message)}</span>
    </div>
    """
  end

  def log_node(%{node: {:group, _header, _children}} = assigns) do
    {:group, header, children} = assigns.node
    assigns = assigns |> assign(:header, header) |> assign(:children, children)

    ~H"""
    <details data-part="log-group">
      <summary data-part="log-group-summary">
        <span data-part="log-ln">{@header.line_number}</span>
        <span data-part="log-ts">{log_ts(@header.ts)}</span>
        <span data-part="log-group-label">
          <span data-part="log-group-chevron"><.chevron_right /></span>{LogFormatter.group_label(
            @header
          )}
        </span>
      </summary>
      <div data-part="log-group-body">
        <.log_tree tree={@children} />
      </div>
    </details>
    """
  end

  # Per-step ranges are computed once (three small ClickHouse queries,
  # no log-body scan); the expanded step's lines are fetched on demand
  # and cached individually. A user who never opens a step pays
  # nothing beyond mount; a job with hundreds of thousands of lines
  # never holds them in the socket.
  defp load_step_logs(socket, number) do
    if Map.has_key?(socket.assigns.step_logs, number) do
      socket
    else
      ranges =
        socket.assigns[:step_line_ranges] ||
          JobLogs.step_line_ranges(
            socket.assigns.job.workflow_job_id,
            socket.assigns.steps
          )

      lines =
        case Map.get(ranges, number) do
          {first, last} ->
            JobLogs.list_step_lines(socket.assigns.job.workflow_job_id, first, last)

          _ ->
            []
        end

      socket
      |> assign(:step_line_ranges, ranges)
      |> assign(:step_logs, Map.put(socket.assigns.step_logs, number, lines))
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

  defp selected_tab("interactive", interactive) do
    if interactive_tab_visible?(interactive), do: "interactive", else: "overview"
  end

  defp selected_tab("logs", _interactive), do: "logs"
  defp selected_tab("metrics", _interactive), do: "metrics"
  defp selected_tab(_, _interactive), do: "overview"

  defp refresh_interactive_state(socket) do
    %{selected_account: selected_account, current_user: current_user, job: job} = socket.assigns
    assign(socket, :interactive, interactive_state(selected_account, current_user, job))
  end

  defp interactive_state(selected_account, current_user, job) do
    macos? = Catalog.fleet_platform(job.fleet_name) == :macos
    running? = job.status in ["claimed", "running"]
    pod_available? = is_binary(job.pod_name) and job.pod_name != ""
    enabled? = FeatureFlags.runners_interactive_enabled?(selected_account)
    can_manage? = Authorization.authorize(:runner_interactive_session_create, current_user, selected_account) == :ok
    vnc_session = InteractiveSessions.current_for_job(selected_account.id, job.workflow_job_id, :vnc)

    %{
      enabled?: enabled?,
      can_manage?: can_manage?,
      macos?: macos?,
      running?: running?,
      pod_available?: pod_available?,
      vnc_requestable?: enabled? and can_manage? and InteractiveSessions.vnc_requestable?(job),
      vnc_session: vnc_session
    }
  end

  defp interactive_session_error(:unsupported_platform),
    do: dgettext("dashboard_runners", "VNC is available for macOS runner jobs.")

  defp interactive_session_error(:job_not_running),
    do: dgettext("dashboard_runners", "VNC can be requested while the macOS runner job is claimed or running.")

  defp interactive_session_error(:pod_unavailable),
    do: dgettext("dashboard_runners", "The runner pod is not available for this job.")

  defp interactive_session_error(_), do: dgettext("dashboard_runners", "The VNC session could not be requested.")
end
