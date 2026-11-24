defmodule TuistWeb.BazelInvocationLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.BazelAnalyticsHelpers,
    only: [parse_page: 1, requested_command: 1, sort_direction: 1, target_patterns_label: 1]

  import TuistWeb.Components.BuildTimeline
  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.ErrorCardSection
  import TuistWeb.Helpers.VCSLinks
  import TuistWeb.Runs.RanByBadge

  alias Noora.Filter
  alias Tuist.Bazel
  alias Tuist.Builds.RecordedSteps
  alias Tuist.Projects.Project
  alias Tuist.ReapiCache
  alias Tuist.RemoteExecution
  alias Tuist.RemoteExecution.Actions
  alias Tuist.Utilities.ByteFormatter
  alias Tuist.Utilities.DateFormatter
  alias Tuist.Utilities.ThroughputFormatter
  alias TuistWeb.BuildTimelineLoader
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  @cache_page_size 20
  @running_refresh_ms 5_000
  # A running invocation lists its latest finished actions; the rest are on
  # its Remote execution tab once it finishes.
  @finished_rows 50
  # Records are best effort, so an action that left the scheduler stays
  # listed as finishing for at most this long while its record is missing.
  @finishing_ms 60_000

  def mount(
        %{"invocation_id" => invocation_id},
        _session,
        %{assigns: %{selected_project: project, selected_account: account}} = socket
      ) do
    project = Tuist.Repo.preload(project, vcs_connection: :github_app_installation)

    case Bazel.get_invocation(project.id, invocation_id) do
      {:ok, invocation} ->
        title = invocation_title(invocation)

        {:ok,
         socket
         |> assign(:selected_project, project)
         |> assign(:invocation, invocation)
         |> assign(
           :failure_category,
           Tuist.BuildMetrics.failure_category(invocation.project_id, "bazel", invocation.invocation_id)
         )
         |> assign(:selected_tab, "overview")
         |> assign(:available_filters, cache_filters("actions"))
         |> assign(:cache_events, [])
         |> assign(:cache_detail_metrics, ReapiCache.empty_invocation_detail_metrics())
         |> assign(:selected_cache_view, "actions")
         |> assign(:cache_filter, "")
         |> assign(:active_cache_filters, [])
         |> assign(:cache_current_page, 1)
         |> assign(:cache_total_pages, 0)
         |> assign(:cache_sort_by, "observed")
         |> assign(:cache_sort_order, "desc")
         |> assign(:bazel_back_label, socket.assigns[:bazel_back_label] || dgettext("dashboard_projects", "Invocations"))
         |> assign(:bazel_back_path, socket.assigns[:bazel_back_path] || "invocations")
         |> assign(:bazel_detail_path, socket.assigns[:bazel_detail_path] || "invocations")
         |> assign(
           :bazel_details_title,
           socket.assigns[:bazel_details_title] || dgettext("dashboard_builds", "Build Details")
         )
         |> assign(:head_title, "#{title} · #{account.name}/#{project.name} · Tuist")
         |> assign(OpenGraph.og_image_assigns("overview"))}

      {:error, :not_found} ->
        mount_running(socket, project, account, invocation_id)
    end
  end

  # An invocation that has not finished has no row yet. Kura reports it when
  # it starts, and the account's scheduler holds its remote actions, so the
  # page shows those until the finished row arrives and replaces it.
  defp mount_running(socket, project, account, invocation_id) do
    with true <- Project.bazel_project?(project),
         %{invocation: %{}} = running <- running_snapshot(project, invocation_id) do
      if connected?(socket), do: Process.send_after(self(), :refresh_running, @running_refresh_ms)

      {:ok,
       socket
       |> assign(:selected_project, project)
       |> assign(:invocation_id, invocation_id)
       |> assign(:running, running)
       |> assign(:finishing, %{})
       |> assign(:execution_rows, execution_rows(running, %{}))
       |> assign(:bazel_back_label, socket.assigns[:bazel_back_label] || dgettext("dashboard_projects", "Invocations"))
       |> assign(:bazel_back_path, socket.assigns[:bazel_back_path] || "invocations")
       |> assign(:bazel_detail_path, socket.assigns[:bazel_detail_path] || "invocations")
       |> assign(
         :bazel_details_title,
         socket.assigns[:bazel_details_title] || dgettext("dashboard_builds", "Build Details")
       )
       |> assign(:head_title, "#{invocation_title(running.invocation)} · #{account.name}/#{project.name} · Tuist")
       |> assign(OpenGraph.og_image_assigns("overview"))}
    else
      _ -> raise NotFoundError, dgettext("dashboard_projects", "Bazel invocation not found.")
    end
  end

  def handle_params(_params, uri, %{assigns: %{running: _}} = socket), do: {:noreply, assign(socket, :uri, URI.new!(uri))}

  def handle_params(params, uri, socket) do
    selected_tab = selected_tab(params)
    project = socket.assigns.selected_project
    invocation = socket.assigns.invocation
    socket = BuildTimelineLoader.select_tab(socket, selected_tab, invocation)
    selected_tab = socket.assigns.selected_tab

    {cache_events, cache_detail_metrics, cache_meta, active_cache_filters, available_filters, cache_sort_by,
     cache_sort_order, selected_cache_view} =
      if selected_tab == "cache" do
        load_cache_events(project.id, invocation, params)
      else
        {[], ReapiCache.empty_invocation_detail_metrics(), %{current_page: 1, total_pages: 0}, [],
         cache_filters("actions"), "observed", "desc", "actions"}
      end

    {:noreply,
     socket
     |> assign(:selected_tab, selected_tab)
     |> assign(:uri, URI.new!(uri))
     |> assign(:cache_events, cache_events)
     |> assign(:cache_detail_metrics, cache_detail_metrics)
     |> assign(:selected_cache_view, selected_cache_view)
     |> assign(:cache_filter, params["cache-filter"] || "")
     |> assign(:cache_current_page, cache_meta.current_page)
     |> assign(:cache_total_pages, cache_meta.total_pages)
     |> assign(:active_cache_filters, active_cache_filters)
     |> assign(:available_filters, available_filters)
     |> assign(:cache_sort_by, cache_sort_by)
     |> assign(:cache_sort_order, cache_sort_order)
     |> assign(:remote_sort_by, if(params["remote-sort-by"] == "started-at", do: "started-at", else: "duration"))
     |> assign(:remote_sort_order, if(params["remote-sort-order"] in ~w(asc desc), do: params["remote-sort-order"]))
     |> load_remote_actions(selected_tab, invocation, params)
     |> BuildTimelineLoader.assign_timeline(selected_tab, invocation)}
  end

  def handle_info(:refresh_running, socket) do
    project = socket.assigns.selected_project
    invocation_id = socket.assigns.invocation_id

    {:noreply, start_async(socket, :refresh_running, fn -> running_snapshot(project, invocation_id) end)}
  end

  defp running_snapshot(project, invocation_id) do
    case RemoteExecution.invocation_activity(project, invocation_id) do
      %{invocation: nil} = activity ->
        activity

      activity ->
        {finished, meta} =
          Actions.list(project.id, invocation_id, %{sort_by: "completed_at", page_size: @finished_rows})

        Map.merge(activity, %{finished: finished, finished_count: meta.total_count})
    end
  end

  # Once the invocation stops running, its finished row has usually arrived,
  # so the page loads again to show it.
  def handle_async(:refresh_running, {:ok, %{invocation: nil}}, socket),
    do:
      {:noreply,
       push_navigate(socket, to: URI.to_string(%URI{path: socket.assigns.uri.path, query: socket.assigns.uri.query}))}

  def handle_async(:refresh_running, result, socket) do
    Process.send_after(self(), :refresh_running, @running_refresh_ms)

    case result do
      {:ok, running} ->
        finishing = finishing(socket.assigns.running, running, socket.assigns.finishing)

        {:noreply,
         socket
         |> assign(:running, running)
         |> assign(:finishing, finishing)
         |> assign(:execution_rows, execution_rows(running, finishing))}

      {:exit, _reason} ->
        {:noreply, socket}
    end
  end

  # The scheduler drops an action when it returns the result to the client,
  # and the gateway sends the action's record after that, so the action
  # would briefly be in neither list. It stays listed as finishing until its
  # record arrives, it shows up in the scheduler again, or @finishing_ms pass.
  defp finishing(previous, current, finishing) do
    now = current.observed_at
    recorded = MapSet.new(current.finished, & &1.operation_id)
    # While the scheduler is unavailable, nothing is known to have left it.
    live = if is_list(current.actions), do: MapSet.new(current.actions, & &1.id)

    left =
      if is_list(previous.actions) and live != nil,
        do:
          for(
            action <- previous.actions,
            action.id not in live,
            into: %{},
            do: {action.id, Map.put(action, :left_at, now)}
          ),
        else: %{}

    finishing
    |> Map.merge(left)
    |> Map.reject(fn {id, action} ->
      MapSet.member?(recorded, id) or (live != nil and MapSet.member?(live, id)) or
        DateTime.diff(now, action.left_at, :millisecond) > @finishing_ms
    end)
  end

  # Live actions first, then finishing ones, then recorded ones, latest
  # finished first. A record replaces its live row as soon as it arrives.
  defp execution_rows(running, finishing) do
    recorded = MapSet.new(running.finished, & &1.operation_id)
    live = if is_list(running.actions), do: Enum.reject(running.actions, &MapSet.member?(recorded, &1.id)), else: []

    Enum.map(live, &live_row(&1, running.observed_at)) ++
      (finishing |> Map.values() |> Enum.sort_by(& &1.left_at, {:desc, DateTime}) |> Enum.map(&finishing_row/1)) ++
      Enum.map(running.finished, &finished_row/1)
  end

  defp live_row(action, observed_at) do
    {label, status} =
      if action.state == "running",
        do: {dgettext("dashboard_builds", "Running"), "in_progress"},
        else: {dgettext("dashboard_builds", "Queued"), "warning"}

    action
    |> scheduled_row(DateTime.diff(observed_at, action.since, :millisecond))
    |> Map.merge(%{label: label, status: status})
  end

  defp finishing_row(action) do
    action
    |> scheduled_row(DateTime.diff(action.left_at, action.since, :millisecond))
    |> Map.merge(%{label: dgettext("dashboard_builds", "Finishing"), status: "in_progress"})
  end

  defp scheduled_row(action, duration_ms) do
    %{
      id: action.id,
      title: action.mnemonic || String.slice(action.action_digest, 0, 12),
      target: action.target,
      machine: machine_label(action.vcpus, action.memory_gb),
      duration_ms: max(duration_ms, 0)
    }
  end

  defp finished_row(action) do
    {label, status} =
      case Actions.status(action) do
        :error -> {dgettext("dashboard_builds", "Error"), "error"}
        :cached -> {dgettext("dashboard_builds", "Cached"), "success"}
        :passed -> {dgettext("dashboard_builds", "Passed"), "success"}
        :failed -> {dgettext("dashboard_builds", "Failed"), "error"}
      end

    %{
      id: action.operation_id,
      label: label,
      status: status,
      title: if(action.mnemonic == "", do: String.slice(action.action_hash, 0, 12), else: action.mnemonic),
      target: if(action.target == "", do: nil, else: action.target),
      machine: machine_label(action.vcpus, action.memory_gb),
      duration_ms: action.duration_ms
    }
  end

  defp machine_label(nil, memory_gb) when memory_gb > 0,
    do: dgettext("dashboard_builds", "%{memory} GB", memory: memory_gb)

  defp machine_label(nil, _memory_gb), do: dgettext("dashboard_builds", "Not recorded")

  defp machine_label(vcpus, memory_gb),
    do: dgettext("dashboard_builds", "%{vcpus} vCPU · %{memory} GB", vcpus: vcpus, memory: memory_gb)

  defp running_action_path(assigns, operation_id),
    do:
      "/#{assigns.selected_account.name}/#{assigns.selected_project.name}/builds/invocations/#{assigns.invocation_id}/remote-actions/#{operation_id}"

  def handle_event("load-timeline", params, socket), do: BuildTimelineLoader.handle_event("load-timeline", params, socket)

  def handle_event("load-timeline-log", %{"event_id" => id, "request_id" => request}, socket)
      when is_binary(id) and byte_size(id) <= 128 and is_integer(request) and request >= 0 do
    case RecordedSteps.get(socket.assigns.invocation, id) do
      {:ok, step} ->
        {:noreply,
         push_event(socket, "timeline-log", %{request_id: request, log: Map.take(step, [:log, :log_truncated])})}

      _ ->
        {:reply, %{error: true}, socket}
    end
  end

  def handle_event("load-timeline-log", _, socket), do: {:reply, %{error: true}, socket}

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params =
      filter_id
      |> Filter.Operations.add_filter_to_query(socket)
      |> Map.put("page", "1")

    socket
    |> push_patch(to: cache_path(socket, updated_params))
    |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
    |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})
    |> then(&{:noreply, &1})
  end

  def handle_event("update_filter", params, socket) do
    updated_params =
      params
      |> Filter.Operations.update_filters_in_query(socket)
      |> Map.put("page", "1")

    socket
    |> push_patch(to: cache_path(socket, updated_params))
    |> push_event("close-dropdown", %{id: "all", all: true})
    |> push_event("close-popover", %{id: "all", all: true})
    |> then(&{:noreply, &1})
  end

  def handle_event("search_cache_requests", %{"search" => search}, socket) do
    query =
      socket.assigns.uri.query
      |> Query.put("cache-filter", search)
      |> Query.put("page", "1")

    {:noreply, push_patch(socket, to: "#{detail_path(socket.assigns)}?#{query}")}
  end

  def render(%{running: _} = assigns) do
    ~H"""
    <div
      id="bazel-invocation"
      class="bazel-invocation"
      phx-hook="PageFavicon"
      data-favicon-status="in_progress"
    >
      <.button
        label={@bazel_back_label}
        data-part="back-button"
        variant="secondary"
        size="medium"
        navigate={"/#{@selected_account.name}/#{@selected_project.name}/#{@bazel_back_path}"}
      >
        <:icon_left><.icon name="arrow_left" /></:icon_left>
      </.button>
      <div data-part="header">
        <div data-part="title-group">
          <div data-part="title">
            <div data-part="badge-processing">
              <div data-part="icon"><.circle_dashed /></div>
            </div>
            <h1 data-part="label">{invocation_title(@running.invocation)}</h1>
          </div>
        </div>
      </div>
      <div data-part="tab-panel">
        <.card title={@bazel_details_title} icon="chart_arcs" data-part="build-details">
          <.card_section data-part="build-details-section">
            <div data-part="metadata-grid">
              <div :if={@running.invocation.command} data-part="metadata-row">
                <div data-part="metadata" data-field="command">
                  <div data-part="title">{dgettext("dashboard_builds", "Command")}</div>
                  <code id="bazel-invocation-command" data-part="command">
                    {requested_command(@running.invocation)}
                  </code>
                </div>
              </div>
              <div data-part="metadata-row">
                <div data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_builds", "Status")}</div>
                  <.badge
                    label={dgettext("dashboard_builds", "Running")}
                    color="primary"
                    style="fill"
                    size="medium"
                  />
                </div>
                <div data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_projects", "Started")}</div>
                  <span data-part="label">
                    {DateFormatter.format_with_timezone(
                      @running.invocation.started_at,
                      @user_timezone
                    )}
                  </span>
                </div>
                <div data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_builds", "Running for")}</div>
                  <span data-part="label">
                    <.history />
                    {DateFormatter.format_duration_from_milliseconds(
                      max(
                        DateTime.diff(
                          @running.observed_at,
                          @running.invocation.started_at,
                          :millisecond
                        ),
                        0
                      ),
                      fractional_seconds: false
                    )}
                  </span>
                </div>
              </div>
              <div :if={@running.invocation.target_patterns != []} data-part="metadata-row">
                <div data-part="metadata" data-field="targets">
                  <div data-part="title">{dgettext("dashboard_projects", "Targets")}</div>
                  <code data-part="command">
                    {target_patterns_label(@running.invocation.target_patterns)}
                  </code>
                </div>
              </div>
              <div data-part="metadata-row">
                <div :if={@running.invocation.git_branch != ""} data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_projects", "Branch")}</div>
                  <.branch_link
                    project={@selected_project}
                    branch={@running.invocation.git_branch}
                    data-part="git-reference"
                  />
                </div>
                <div :if={@running.invocation.git_commit_sha != ""} data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_projects", "Commit")}</div>
                  <.commit_link
                    project={@selected_project}
                    commit_sha={@running.invocation.git_commit_sha}
                    data-part="git-reference"
                  />
                </div>
                <div data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_projects", "Invocation ID")}</div>
                  <code data-part="identifier">{@invocation_id}</code>
                </div>
              </div>
            </div>
          </.card_section>
        </.card>
        <.card title={dgettext("dashboard_builds", "Executions")} icon="history">
          <%= if @execution_rows == [] do %>
            <.empty_card_section
              id="running-remote-actions"
              title={
                if @running.actions == :unavailable,
                  do: dgettext("dashboard_builds", "Running executions are unavailable"),
                  else: dgettext("dashboard_builds", "No executions are running or queued")
              }
              data-part="remote-execution-section"
            >
              <:image>
                <img src={~p"/images/empty_table_light.png"} data-theme="light" loading="lazy" />
                <img src={~p"/images/empty_table_dark.png"} data-theme="dark" loading="lazy" />
              </:image>
            </.empty_card_section>
          <% else %>
            <.card_section data-part="remote-execution-section">
              <.alert
                :if={@running.actions == :unavailable}
                id="running-remote-actions-unavailable"
                type="secondary"
                status="warning"
                size="small"
                title={dgettext("dashboard_builds", "Running executions are unavailable")}
              />
              <.table
                id="running-remote-actions"
                rows={@execution_rows}
                row_key={& &1.id}
                row_navigate={&running_action_path(assigns, &1.id)}
              >
                <:col :let={row} label={dgettext("dashboard_builds", "Status")}>
                  <.status_badge_cell label={row.label} status={row.status} />
                </:col>
                <:col :let={row} label={dgettext("dashboard_projects", "Action")}>
                  <div data-part="trace-action">
                    <.text_and_description_cell label={row.title} description={row.target} />
                  </div>
                </:col>
                <:col :let={row} label={dgettext("dashboard_builds", "Machine")}>
                  <.text_cell label={row.machine} />
                </:col>
                <:col :let={row} label={dgettext("dashboard_projects", "Duration")}>
                  <.text_cell
                    label={
                      if row.duration_ms,
                        do:
                          DateFormatter.format_duration_from_milliseconds(row.duration_ms,
                            fractional_seconds: false
                          ),
                        else: dgettext("dashboard_builds", "Not recorded")
                    }
                    icon="history"
                  />
                </:col>
              </.table>
              <span
                :if={@running.finished_count > length(@running.finished)}
                data-part="finished-note"
              >
                {dgettext(
                  "dashboard_builds",
                  "Showing the latest %{shown} of %{count} finished executions. The invocation's Remote execution tab lists all of them once it finishes.",
                  shown: length(@running.finished),
                  count: @running.finished_count
                )}
              </span>
            </.card_section>
          <% end %>
        </.card>
      </div>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div
      id="bazel-invocation"
      class="bazel-invocation"
      phx-hook="PageFavicon"
      data-favicon-status={@invocation.status}
    >
      <.button
        label={@bazel_back_label}
        data-part="back-button"
        variant="secondary"
        size="medium"
        navigate={"/#{@selected_account.name}/#{@selected_project.name}/#{@bazel_back_path}"}
      >
        <:icon_left><.icon name="arrow_left" /></:icon_left>
      </.button>
      <div data-part="header">
        <div data-part="title-group">
          <div data-part="title">
            <div :if={@invocation.status == "success"} data-part="badge-success">
              <div data-part="icon"><.circle_check /></div>
            </div>
            <div :if={@invocation.status != "success"} data-part="badge-failure">
              <div data-part="icon"><.alert_circle /></div>
            </div>
            <h1 data-part="label">{invocation_title(@invocation)}</h1>
          </div>
        </div>
      </div>
      <.tab_menu_horizontal data-part="tabs">
        <.tab_menu_horizontal_item
          label={dgettext("dashboard_projects", "Overview")}
          patch={tab_path(assigns, "overview")}
          selected={@selected_tab == "overview"}
        />
        <.tab_menu_horizontal_item
          :if={@timeline_available}
          label={dgettext("dashboard_builds", "Timeline")}
          patch={tab_path(assigns, "timeline")}
          selected={@selected_tab == "timeline"}
        />
        <.tab_menu_horizontal_item
          label={dgettext("dashboard_projects", "Bazel Cache")}
          patch={tab_path(assigns, "cache")}
          selected={@selected_tab == "cache"}
        />
        <.tab_menu_horizontal_item
          label={dgettext("dashboard_builds", "Remote execution")}
          patch={tab_path(assigns, "remote-execution")}
          selected={@selected_tab == "remote-execution"}
        />
      </.tab_menu_horizontal>
      <.card
        :if={@selected_tab == "remote-execution"}
        title={dgettext("dashboard_builds", "Executions")}
        icon="history"
      >
        <:actions>
          <div data-part="phase-legend">
            <span :for={{phase, _field, label} <- remote_phases()} data-phase={phase}>
              {label}
            </span>
          </div>
        </:actions>
        <.card_section
          data-part="remote-execution-section"
          data-state={if @remote_actions.ok? && @remote_actions.loading, do: "refreshing"}
          aria-busy={if @remote_actions.loading, do: "true", else: "false"}
        >
          <div
            :if={!(@remote_actions.ok? && @remote_actions.result.steps == [])}
            data-part="filters"
          >
            <.dropdown
              id="remote-actions-sort-by"
              label={remote_sort_label(@remote_sort_by)}
              secondary_text={dgettext("dashboard_builds", "Sort by:")}
            >
              <.dropdown_item
                :for={sort_by <- ~w(duration started-at)}
                value={sort_by}
                label={remote_sort_label(sort_by)}
                patch={remote_path(assigns, 1, sort_by)}
                data-selected={@remote_sort_by == sort_by}
              >
                <:right_icon :if={@remote_sort_by == sort_by}><.check /></:right_icon>
              </.dropdown_item>
            </.dropdown>
          </div>
          <%!-- A re-sort or page change keeps the current rows until the new ones arrive. --%>
          <.async_result :let={result} assign={@remote_actions}>
            <:loading>
              <div data-part="skeleton">
                <.skeleton_box :for={_ <- 1..5} width="100%" height="44px" border_radius="8px" />
              </div>
            </:loading>
            <:failed><.error_state /></:failed>
            <.table
              :if={result.steps != []}
              id="remote-actions-table"
              rows={trace_rows(result)}
              row_key={&("remote-action-" <> &1.action.id)}
              row_navigate={&(&1.operation_id && remote_action_path(assigns, &1.operation_id))}
            >
              <:col :let={row} label={dgettext("dashboard_projects", "Action")}>
                <div data-part="trace-action">
                  <.text_and_description_cell
                    label={row.action.title}
                    description={row.action.target}
                  />
                </div>
              </:col>
              <:col
                :let={row}
                label={dgettext("dashboard_builds", "Started at")}
                patch={remote_header_path(assigns, "started-at")}
                sort_order={remote_sort_order(assigns, "started-at")}
              >
                <.text_cell label={remote_duration(row.action.start_ms)} />
              </:col>
              <:col :let={row} label={dgettext("dashboard_builds", "Phases")}>
                <%!-- Noora's tooltip renders only a title, so this reuses its hook with
                     the chart tooltip's card to list each phase like a chart series. --%>
                <div
                  id={"remote-action-phases-" <> row.action.id}
                  class="noora-tooltip"
                  phx-hook="NooraTooltip"
                  data-open-delay="250"
                  data-close-delay="150"
                  data-positioning-placement="top"
                >
                  <div data-part="trigger">
                    <span data-part="phase-bar" style={"width: #{row.width}%"}>
                      <span
                        :for={segment <- row.segments}
                        data-phase={segment.phase}
                        style={"flex-basis: #{segment.share}%"}
                      />
                    </span>
                  </div>
                  <div data-part="positioner">
                    <div data-part="content" class="noora-chart-tooltip">
                      <span data-part="title">{row.action.title}</span>
                      <div class="noora-line-divider">
                        <div data-part="line"></div>
                      </div>
                      <div :for={phase <- row.phases} data-part="series-item" data-phase={phase.phase}>
                        <span data-part="dot"></span>
                        <span data-part="label">{phase.label}</span>
                        <span data-part="value">{remote_duration(phase.ms)}</span>
                      </div>
                    </div>
                  </div>
                </div>
              </:col>
              <:col
                :let={row}
                label={dgettext("dashboard_projects", "Duration")}
                patch={remote_header_path(assigns, "duration")}
                sort_order={remote_sort_order(assigns, "duration")}
              >
                <.text_cell label={remote_duration(row.action.duration_ms)} icon="history" />
              </:col>
            </.table>
            <div :if={result.steps == []} id="remote-actions-table">
              <.table_empty_state
                icon="history"
                title={dgettext("dashboard_builds", "No remote action timings")}
                subtitle={
                  dgettext(
                    "dashboard_builds",
                    "A profile with unambiguous action and server phase intervals is required. Older or incomplete profiles may not contain these timings. Upload a new profile to see them."
                  )
                }
              />
            </div>
            <.pagination_group
              :if={result.pagination_metadata.total_pages > 1}
              current_page={result.pagination_metadata.current_page}
              number_of_pages={result.pagination_metadata.total_pages}
              page_patch={fn page -> remote_path(assigns, page) end}
            />
          </.async_result>
        </.card_section>
      </.card>
      <section :if={@selected_tab == "timeline"}>
        <.build_timeline_section
          timeline={@timeline}
          duration={@invocation.duration_ms}
          version={@timeline_version}
          source="bazel"
          url={
            ~p"/#{@selected_project.account.name}/#{@selected_project.name}/builds/invocations/#{@invocation.invocation_id}/timeline.json"
          }
          trace_url={
            ~p"/#{@selected_project.account.name}/#{@selected_project.name}/builds/invocations/#{@invocation.invocation_id}/trace.json"
          }
        />
      </section>
      <div :if={@selected_tab == "overview"} data-part="tab-panel">
        <.card title={@bazel_details_title} icon="chart_arcs" data-part="build-details">
          <.card_section data-part="build-details-section">
            <div data-part="metadata-grid">
              <div data-part="metadata-row">
                <div data-part="metadata" data-field="command">
                  <div data-part="title">{dgettext("dashboard_builds", "Command")}</div>
                  <code id="bazel-invocation-command" data-part="command">
                    {requested_command(@invocation)}
                  </code>
                </div>
              </div>
              <div data-part="metadata-row">
                <div data-part="metadata">
                  <div data-part="title">
                    {dgettext("dashboard_builds", "Status")}
                  </div>
                  <.badge
                    label={invocation_result_label(@invocation)}
                    color={invocation_result_badge_color(@invocation.status)}
                    style="fill"
                    size="medium"
                  />
                </div>
                <div data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_builds", "Built by")}</div>
                  <.run_ran_by_badge_cell run={@invocation} />
                </div>
                <div data-part="metadata">
                  <div data-part="title">
                    {dgettext("dashboard_builds", "Build duration")}
                  </div>
                  <span data-part="label">
                    <.history />
                    {DateFormatter.format_duration_from_milliseconds(@invocation.duration_ms)}
                  </span>
                </div>
                <div data-part="metadata">
                  <div data-part="title">
                    {dgettext("dashboard_builds", "Built at")}
                  </div>
                  <span data-part="label">
                    {DateFormatter.format_with_timezone(@invocation.finished_at, @user_timezone)}
                  </span>
                </div>
              </div>
              <div data-part="metadata-row">
                <div data-part="metadata">
                  <div data-part="title">
                    {dgettext("dashboard_projects", "Started")}
                  </div>
                  <span data-part="label">
                    {DateFormatter.format_with_timezone(@invocation.started_at, @user_timezone)}
                  </span>
                </div>
                <div data-part="metadata" data-field="targets">
                  <div data-part="title">{dgettext("dashboard_projects", "Targets")}</div>
                  <code data-part="command">{target_patterns_label(@invocation.target_patterns)}</code>
                </div>
              </div>
              <div data-part="metadata-row">
                <div :if={connected_to_repository?(@selected_project)} data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_projects", "Repository")}</div>
                  <.repository_link project={@selected_project} data-part="git-reference" />
                </div>
                <div :if={@invocation.git_branch != ""} data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_projects", "Branch")}</div>
                  <.branch_link
                    project={@selected_project}
                    branch={@invocation.git_branch}
                    data-part="git-reference"
                  />
                </div>
                <div :if={@invocation.git_commit_sha != ""} data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_projects", "Commit")}</div>
                  <.commit_link
                    project={@selected_project}
                    commit_sha={@invocation.git_commit_sha}
                    data-part="git-reference"
                  />
                </div>
                <div data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_projects", "Invocation ID")}</div>
                  <code data-part="identifier">{@invocation.invocation_id}</code>
                </div>
              </div>
            </div>
            <TuistWeb.Components.BuildHealth.category_detail category={@failure_category} />
            <TuistWeb.Components.BuildMetadata.build_metadata values={
              @invocation.custom_values || %{}
            } />
          </.card_section>
        </.card>
        <TuistWeb.Components.BuildMetadata.environment_metadata
          values={@invocation.custom_values || %{}}
          fields={[{dgettext("dashboard_projects", "Bazel version"), @invocation.bazel_version}]}
        />
      </div>
      <div :if={@selected_tab == "cache"} data-part="tab-panel">
        <.cache_tab
          cache={@invocation.cache}
          cache_events={@cache_events}
          cache_detail_metrics={@cache_detail_metrics}
          selected_cache_view={@selected_cache_view}
          cache_filter={@cache_filter}
          active_cache_filters={@active_cache_filters}
          available_filters={@available_filters}
          cache_current_page={@cache_current_page}
          cache_total_pages={@cache_total_pages}
          cache_sort_by={@cache_sort_by}
          cache_sort_order={@cache_sort_order}
          uri={@uri}
          path={detail_path(assigns)}
          remote_cache_enabled={remote_cache_used?(@invocation)}
          table_id="bazel-invocation-cache-events-table"
          filter_id="bazel-invocation-cache-filter-dropdown"
          widget_id_prefix="bazel-invocation-cache"
          search_id="bazel-invocation-cache-search"
        />
      </div>
    </div>
    """
  end

  attr :cache, :map, required: true
  attr :cache_events, :list, required: true
  attr :cache_detail_metrics, :map, required: true
  attr :selected_cache_view, :string, required: true
  attr :cache_filter, :string, required: true
  attr :active_cache_filters, :list, required: true
  attr :available_filters, :list, required: true
  attr :cache_current_page, :integer, required: true
  attr :cache_total_pages, :integer, required: true
  attr :cache_sort_by, :string, required: true
  attr :cache_sort_order, :string, required: true
  attr :uri, :map, required: true
  attr :path, :string, required: true
  attr :remote_cache_enabled, :boolean, required: true
  attr :table_id, :string, required: true
  attr :filter_id, :string, required: true
  attr :widget_id_prefix, :string, required: true
  attr :search_id, :string, required: true

  def cache_tab(assigns) do
    ~H"""
    <.card
      title={dgettext("dashboard_projects", "Cache Summary")}
      icon="chart_arcs"
      data-part="cache-summary-card"
    >
      <.card_section data-part="cache-summary-section">
        <.widget
          id={@widget_id_prefix <> "-action-hits"}
          title={dgettext("dashboard_projects", "Action hits")}
          description={
            dgettext(
              "dashboard_projects",
              "Action cache lookups that found a result in the remote cache."
            )
          }
          value={@cache.hits}
          empty={cache_summary_empty?(@cache)}
        />
        <.widget
          id={@widget_id_prefix <> "-action-misses"}
          title={dgettext("dashboard_projects", "Action misses")}
          description={
            dgettext(
              "dashboard_projects",
              "Action cache lookups that did not find a result in the remote cache."
            )
          }
          value={@cache.misses}
          empty={cache_summary_empty?(@cache)}
        />
        <.widget
          id={@widget_id_prefix <> "-hit-rate"}
          title={dgettext("dashboard_projects", "Hit rate")}
          description={
            dgettext(
              "dashboard_projects",
              "The percentage of action cache lookups that found a result in the remote cache."
            )
          }
          value={cache_hit_rate(@cache)}
          empty={cache_summary_empty?(@cache) or @cache.hits + @cache.misses == 0}
        />
        <.widget
          id={@widget_id_prefix <> "-downloads"}
          title={dgettext("dashboard_projects", "Content downloaded")}
          description={
            dgettext(
              "dashboard_projects",
              "Total size of build outputs downloaded from the remote cache. Excludes action cache lookups, which return metadata rather than outputs."
            )
          }
          value={ByteFormatter.format_bytes(@cache.content_download_bytes)}
          empty={cache_summary_empty?(@cache)}
        />
        <.widget
          id={@widget_id_prefix <> "-uploads"}
          title={dgettext("dashboard_projects", "Content uploaded")}
          description={
            dgettext(
              "dashboard_projects",
              "Total size of build outputs uploaded to the remote cache. Excludes action cache writes, which store metadata rather than outputs."
            )
          }
          value={ByteFormatter.format_bytes(@cache.content_upload_bytes)}
          empty={cache_summary_empty?(@cache)}
        />
      </.card_section>
    </.card>
    <.tab_menu_horizontal data-part="cache-views">
      <.tab_menu_horizontal_item
        label={dgettext("dashboard_projects", "Cacheable Actions")}
        selected={@selected_cache_view == "actions"}
        patch={cache_view_patch(@path, @uri, "actions")}
      />
      <.tab_menu_horizontal_item
        label={dgettext("dashboard_projects", "Content Objects")}
        selected={@selected_cache_view == "content-objects"}
        patch={cache_view_patch(@path, @uri, "content-objects")}
      />
    </.tab_menu_horizontal>
    <.card
      title={dgettext("dashboard_projects", "Bazel Cache")}
      icon="database"
      data-part="cache-requests-card"
    >
      <.card_section data-part="bazel-cache-card-section">
        <.empty_card_section
          :if={cache_requests_empty_state?(@cache_events, @cache_filter, @active_cache_filters)}
          title={cache_requests_empty_state_title(@remote_cache_enabled, @selected_cache_view)}
          data-part="empty-cache-requests-card-section"
        >
          <:image>
            <img
              src={~p"/images/empty_table_light.png"}
              data-theme="light"
              loading="lazy"
              decoding="async"
            />
            <img
              src={~p"/images/empty_table_dark.png"}
              data-theme="dark"
              loading="lazy"
              decoding="async"
            />
          </:image>
        </.empty_card_section>
        <div
          :if={not cache_requests_empty_state?(@cache_events, @cache_filter, @active_cache_filters)}
          data-part="cache-requests-content"
        >
          <.card_section
            :if={@selected_cache_view == "actions" and @cache.hits + @cache.misses > 0}
            data-part="cache-breakdown-card-section"
          >
            <div data-part="title">
              <span data-part="label">{dgettext("dashboard_projects", "Action cache lookups:")}</span>
              <span data-part="value">{format_number(@cache.hits + @cache.misses)}</span>
            </div>
            <.chart
              id={@widget_id_prefix <> "-actions-breakdown"}
              type="bar"
              series={cache_action_breakdown_series(@cache)}
              extra_options={
                cache_breakdown_chart_options(dgettext("dashboard_projects", "Action cache lookups"))
              }
              x_axis_min={0}
              x_axis_max={@cache.hits + @cache.misses}
            />
          </.card_section>
          <.card_section
            :if={
              @selected_cache_view == "content-objects" and
                @cache_detail_metrics.content_download_count +
                  @cache_detail_metrics.content_upload_count > 0
            }
            data-part="cache-breakdown-card-section"
          >
            <div data-part="title">
              <span data-part="label">{dgettext("dashboard_projects", "Content objects:")}</span>
              <span data-part="value">
                {@cache_detail_metrics.content_download_count +
                  @cache_detail_metrics.content_upload_count}
              </span>
            </div>
            <.chart
              id={@widget_id_prefix <> "-content-breakdown"}
              type="bar"
              series={cache_content_breakdown_series(@cache_detail_metrics)}
              extra_options={
                cache_breakdown_chart_options(dgettext("dashboard_projects", "Content objects"))
              }
              x_axis_min={0}
              x_axis_max={
                @cache_detail_metrics.content_download_count +
                  @cache_detail_metrics.content_upload_count
              }
            />
          </.card_section>
          <div :if={@selected_cache_view == "actions"} data-part="latency-widgets">
            <.widget
              id={@widget_id_prefix <> "-read-latency"}
              title={dgettext("dashboard_projects", "Avg. latency reading cache keys")}
              description={
                dgettext(
                  "dashboard_projects",
                  "Time to read action cache keys, including both remote hits and misses."
                )
              }
              value={
                DateFormatter.format_duration_from_milliseconds(
                  @cache_detail_metrics.action_read_latency_ms
                )
              }
              empty={@cache_detail_metrics.action_read_count == 0}
              empty_label={dgettext("dashboard_projects", "No data")}
            />
            <.widget
              id={@widget_id_prefix <> "-write-latency"}
              title={dgettext("dashboard_projects", "Avg. latency writing cache keys")}
              description={
                dgettext("dashboard_projects", "Time to write action results to the remote cache.")
              }
              value={
                DateFormatter.format_duration_from_milliseconds(
                  @cache_detail_metrics.action_write_latency_ms
                )
              }
              empty={@cache_detail_metrics.action_write_count == 0}
              empty_label={dgettext("dashboard_projects", "No data")}
            />
          </div>
          <div :if={@selected_cache_view == "content-objects"} data-part="throughput-widgets">
            <.widget
              id={@widget_id_prefix <> "-download-throughput"}
              title={dgettext("dashboard_projects", "Download throughput")}
              description={
                dgettext("dashboard_projects", "Average throughput for downloaded content objects.")
              }
              value={
                ThroughputFormatter.format_throughput(
                  @cache_detail_metrics.content_download_throughput_bytes_per_second
                )
              }
              empty={@cache_detail_metrics.content_download_throughput_bytes_per_second == 0}
              empty_label={dgettext("dashboard_projects", "No data")}
            />
            <.widget
              id={@widget_id_prefix <> "-upload-throughput"}
              title={dgettext("dashboard_projects", "Upload throughput")}
              description={
                dgettext("dashboard_projects", "Average throughput for uploaded content objects.")
              }
              value={
                ThroughputFormatter.format_throughput(
                  @cache_detail_metrics.content_upload_throughput_bytes_per_second
                )
              }
              empty={@cache_detail_metrics.content_upload_throughput_bytes_per_second == 0}
              empty_label={dgettext("dashboard_projects", "No data")}
            />
          </div>
          <div data-part="filters">
            <.form
              id={@search_id <> "-form"}
              for={%{}}
              phx-change="search_cache_requests"
              phx-debounce="200"
            >
              <.text_input
                type="search"
                id={@search_id}
                name="search"
                placeholder={dgettext("dashboard_builds", "Search...")}
                show_suffix={false}
                data-part="search"
                value={@cache_filter}
              />
            </.form>
            <.filter_dropdown
              id={@filter_id}
              label={dgettext("dashboard_projects", "Filter")}
              available_filters={@available_filters}
              active_filters={@active_cache_filters}
            />
          </div>
          <div :if={Enum.any?(@active_cache_filters)} data-part="active-filters">
            <.active_filter :for={filter <- @active_cache_filters} filter={filter} />
          </div>
          <.table id={@table_id} rows={@cache_events}>
            <:col
              :let={event}
              :if={@selected_cache_view == "actions"}
              label={dgettext("dashboard_projects", "Action")}
              patch={cache_column_patch(@path, @uri, @cache_sort_by, @cache_sort_order, "action")}
              sort_order={@cache_sort_by == "action" && @cache_sort_order}
            >
              <.text_cell label={cache_event_action(event)} />
            </:col>
            <:col
              :let={event}
              :if={@selected_cache_view == "content-objects"}
              label={dgettext("dashboard_projects", "Key")}
              patch={cache_column_patch(@path, @uri, @cache_sort_by, @cache_sort_order, "digest")}
              sort_order={@cache_sort_by == "digest" && @cache_sort_order}
            >
              <.text_cell label={short_cache_digest(event.action_digest)} title={event.action_digest} />
            </:col>
            <:col
              :let={event}
              label={cache_status_column_label(@selected_cache_view)}
              patch={cache_column_patch(@path, @uri, @cache_sort_by, @cache_sort_order, "outcome")}
              sort_order={@cache_sort_by == "outcome" && @cache_sort_order}
            >
              <.status_badge_cell
                label={cache_outcome_label(event, @selected_cache_view)}
                status={cache_outcome_status(event.outcome)}
              />
            </:col>
            <:col
              :let={event}
              :if={@selected_cache_view == "actions"}
              label={dgettext("dashboard_projects", "Target")}
              patch={cache_column_patch(@path, @uri, @cache_sort_by, @cache_sort_order, "target")}
              sort_order={@cache_sort_by == "target" && @cache_sort_order}
            >
              <.text_cell label={cache_target_label(event.target_label)} />
            </:col>
            <:col
              :let={event}
              :if={@selected_cache_view == "actions"}
              label={dgettext("dashboard_projects", "Cache key")}
              patch={cache_column_patch(@path, @uri, @cache_sort_by, @cache_sort_order, "digest")}
              sort_order={@cache_sort_by == "digest" && @cache_sort_order}
            >
              <.text_cell
                label={short_cache_digest(event.action_digest)}
                sublabel={format_cache_size(event.size)}
                title={event.action_digest}
              />
            </:col>
            <:col
              :let={event}
              :if={@selected_cache_view == "content-objects"}
              label={dgettext("dashboard_projects", "Size")}
            >
              <.text_cell label={ByteFormatter.format_bytes(event.size)} />
            </:col>
            <:col
              :let={event}
              label={dgettext("dashboard_projects", "Latency")}
              patch={cache_column_patch(@path, @uri, @cache_sort_by, @cache_sort_order, "latency")}
              sort_order={@cache_sort_by == "latency" && @cache_sort_order}
            >
              <.text_cell
                label={DateFormatter.format_duration_from_milliseconds(event.duration_ms)}
                icon="history"
              />
            </:col>
            <:col
              :let={event}
              label={dgettext("dashboard_projects", "Observed")}
              patch={cache_column_patch(@path, @uri, @cache_sort_by, @cache_sort_order, "observed")}
              sort_order={@cache_sort_by == "observed" && @cache_sort_order}
            >
              <.text_cell sublabel={DateFormatter.from_now(event.observed_at)} />
            </:col>
            <:empty_state>
              <.table_empty_state
                icon="filters"
                title={dgettext("dashboard_projects", "No matching cache requests")}
                subtitle={dgettext("dashboard_projects", "Try changing or clearing your filters.")}
              />
            </:empty_state>
          </.table>
          <.pagination_group
            :if={@cache_total_pages > 1}
            current_page={@cache_current_page}
            number_of_pages={@cache_total_pages}
            page_patch={fn page -> cache_page_patch(@path, @uri, page) end}
          />
        </div>
      </.card_section>
    </.card>
    """
  end

  def cache_filters(selected_cache_view) do
    [
      %Filter.Filter{
        id: "outcome",
        field: :outcome,
        display_name: cache_status_column_label(selected_cache_view),
        type: :option,
        options: ["hit", "miss", "write"],
        options_display_names: cache_filter_outcome_labels(selected_cache_view),
        operator: :==,
        value: nil
      }
    ]
  end

  defp load_cache_events(project_id, invocation, params) do
    cache_sort_by = params["cache-sort-by"] || "observed"
    cache_sort_order = params["cache-sort-order"] || "desc"
    cache_query_options = Bazel.invocation_cache_query_options(invocation)
    selected_cache_view = selected_cache_view(params)
    available_filters = cache_filters(selected_cache_view)

    active_cache_filters =
      Filter.Operations.decode_filters_from_query(params, available_filters)

    {cache_events, cache_meta} =
      ReapiCache.list_invocation_cache_events(
        project_id,
        invocation.invocation_id,
        %{
          filters:
            [cache_operation_flop_filter(selected_cache_view)] ++
              cache_text_flop_filters(params["cache-filter"], selected_cache_view) ++
              Filter.Operations.convert_filters_to_flop(active_cache_filters),
          order_by: [cache_sort_field(cache_sort_by), :id],
          order_directions: [sort_direction(cache_sort_order), :asc],
          page: parse_page(params["page"]),
          page_size: @cache_page_size
        },
        cache_query_options
      )

    cache_detail_metrics =
      ReapiCache.invocation_detail_metrics(project_id, invocation.invocation_id, cache_query_options)

    {cache_events, cache_detail_metrics, cache_meta, active_cache_filters, available_filters, cache_sort_by,
     cache_sort_order, selected_cache_view}
  end

  defp cache_operation_flop_filter("content-objects"), do: %{field: :operation, op: :==, value: "cas"}
  defp cache_operation_flop_filter(_selected_cache_view), do: %{field: :operation, op: :==, value: "action_cache"}

  defp cache_text_flop_filters(nil, _selected_cache_view), do: []
  defp cache_text_flop_filters("", _selected_cache_view), do: []
  defp cache_text_flop_filters(search, "content-objects"), do: [%{field: :action_digest, op: :=~, value: search}]
  defp cache_text_flop_filters(search, _selected_cache_view), do: [%{field: :action_search, op: :=~, value: search}]

  defp cache_requests_empty_state?(cache_events, cache_filter, active_cache_filters) do
    Enum.empty?(cache_events) and cache_filter == "" and Enum.empty?(active_cache_filters)
  end

  defp cache_requests_empty_state_title(false, _selected_cache_view),
    do: dgettext("dashboard_projects", "This invocation did not use a remote cache.")

  defp cache_requests_empty_state_title(true, "content-objects"),
    do: dgettext("dashboard_projects", "No content object transfers were observed for this invocation.")

  defp cache_requests_empty_state_title(true, _selected_cache_view),
    do: dgettext("dashboard_projects", "No action cache requests were observed for this invocation.")

  # One decision for the whole card. Previously only the hit-rate tile opted
  # into an empty state, so an invocation with no cache activity rendered
  # "0 / 0 / No data yet / 0 B / 0 B" - the inconsistency read as a broken
  # widget rather than an absence of data.
  defp cache_summary_empty?(cache) do
    cache.hits + cache.misses == 0 and cache.content_download_bytes == 0 and
      cache.content_upload_bytes == 0
  end

  defp cache_hit_rate(%{hit_rate: nil}), do: "0%"
  defp cache_hit_rate(cache), do: "#{cache.hit_rate}%"

  defp cache_event_action(%{action_display_name: name}) when is_binary(name) and name != "", do: name
  defp cache_event_action(%{action_mnemonic: ""}), do: dgettext("dashboard_projects", "Action cache lookup")
  defp cache_event_action(event), do: event.action_mnemonic
  defp cache_target_label(""), do: dgettext("dashboard_projects", "Unknown")
  defp cache_target_label(target_label), do: target_label
  defp short_cache_digest(""), do: dgettext("dashboard_projects", "No digest")
  defp short_cache_digest(digest), do: String.slice(digest, 0, 12) <> if(byte_size(digest) > 12, do: "…", else: "")
  defp format_cache_size(0), do: nil
  defp format_cache_size(size), do: ByteFormatter.format_bytes(size)
  defp cache_outcome_label(%{outcome: "hit"}, "content-objects"), do: dgettext("dashboard_projects", "Download")
  defp cache_outcome_label(%{outcome: "write"}, "content-objects"), do: dgettext("dashboard_projects", "Upload")
  defp cache_outcome_label(%{outcome: "hit"}, _selected_cache_view), do: dgettext("dashboard_projects", "Remote")
  defp cache_outcome_label(%{outcome: "miss"}, _selected_cache_view), do: dgettext("dashboard_projects", "Missed")
  defp cache_outcome_label(_event, _selected_cache_view), do: dgettext("dashboard_projects", "Stored")
  defp cache_status_column_label("actions"), do: dgettext("dashboard_projects", "Hit")
  defp cache_status_column_label(_selected_cache_view), do: dgettext("dashboard_projects", "Status")

  defp cache_filter_outcome_labels("actions") do
    %{
      "hit" => dgettext("dashboard_projects", "Remote"),
      "miss" => dgettext("dashboard_projects", "Missed"),
      "write" => dgettext("dashboard_projects", "Stored")
    }
  end

  defp cache_filter_outcome_labels(_selected_cache_view) do
    %{
      "hit" => dgettext("dashboard_projects", "Download"),
      "miss" => dgettext("dashboard_projects", "Missed"),
      "write" => dgettext("dashboard_projects", "Upload")
    }
  end

  defp cache_outcome_status("hit"), do: "success"
  defp cache_outcome_status("miss"), do: "attention"
  defp cache_outcome_status(_), do: "success"

  defp cache_action_breakdown_series(cache) do
    [
      %{
        name: dgettext("dashboard_projects", "Remote"),
        type: "bar",
        stack: "total",
        emphasis: %{focus: "series"},
        data: [cache.hits],
        color: "var:hits-chart-legend-remote",
        itemStyle: %{borderRadius: cache_breakdown_border_radius(cache.hits, cache.misses, :first)}
      },
      %{
        name: dgettext("dashboard_projects", "Missed"),
        type: "bar",
        stack: "total",
        emphasis: %{focus: "series"},
        data: [cache.misses],
        color: "var:hits-chart-legend-missed",
        itemStyle: %{borderRadius: cache_breakdown_border_radius(cache.hits, cache.misses, :second)}
      }
    ]
  end

  defp cache_content_breakdown_series(metrics) do
    [
      %{
        name: dgettext("dashboard_projects", "Download"),
        type: "bar",
        stack: "total",
        emphasis: %{focus: "series"},
        data: [metrics.content_download_count],
        color: "var:hits-chart-legend-remote",
        itemStyle: %{
          borderRadius:
            cache_breakdown_border_radius(metrics.content_download_count, metrics.content_upload_count, :first)
        }
      },
      %{
        name: dgettext("dashboard_projects", "Upload"),
        type: "bar",
        stack: "total",
        emphasis: %{focus: "series"},
        data: [metrics.content_upload_count],
        color: "var:hits-chart-legend-local",
        itemStyle: %{
          borderRadius:
            cache_breakdown_border_radius(metrics.content_download_count, metrics.content_upload_count, :second)
        }
      }
    ]
  end

  defp cache_breakdown_chart_options(label) do
    %{
      animation: false,
      tooltip: %{trigger: "axis", axisPointer: %{type: "none"}},
      legend: %{
        left: "-0.3%",
        top: "bottom",
        orient: "horizontal",
        textStyle: %{
          color: "var:noora-surface-label-primary",
          fontFamily: "monospace",
          fontWeight: 400,
          fontSize: 10,
          lineHeight: 12
        },
        icon:
          "path://M0 6C0 4.89543 0.895431 4 2 4H6C7.10457 4 8 4.89543 8 6C8 7.10457 7.10457 8 6 8H2C0.895431 8 0 7.10457 0 6Z",
        itemWidth: 8,
        itemHeight: 4
      },
      grid: %{width: "99%", left: "0%", height: "60%", top: "0%"},
      xAxis: %{type: "value", axisLabel: %{show: false}, splitLine: %{show: false}},
      yAxis: %{
        type: "category",
        data: [label],
        axisLabel: %{show: false}
      }
    }
  end

  defp cache_breakdown_border_radius(first_count, second_count, :first) do
    cond do
      first_count == 0 -> [0, 0, 0, 0]
      second_count == 0 -> [8, 8, 8, 8]
      true -> [8, 0, 0, 8]
    end
  end

  defp cache_breakdown_border_radius(first_count, second_count, :second) do
    cond do
      second_count == 0 -> [0, 0, 0, 0]
      first_count == 0 -> [8, 8, 8, 8]
      true -> [0, 8, 8, 0]
    end
  end

  defp selected_cache_view(%{"cache-view" => "content-objects"}), do: "content-objects"
  defp selected_cache_view(_params), do: "actions"

  defp cache_view_patch(path, uri, selected_cache_view) do
    uri.query
    |> URI.decode_query()
    |> Map.put("cache-view", selected_cache_view)
    |> Map.put("page", "1")
    |> Map.delete("cache-filter")
    |> Map.put("cache-sort-by", "observed")
    |> Map.put("cache-sort-order", "desc")
    |> URI.encode_query()
    |> then(&"#{path}?#{&1}")
  end

  defp cache_sort_field("target"), do: :target_label
  defp cache_sort_field("outcome"), do: :outcome
  defp cache_sort_field("action"), do: :action_display_name
  defp cache_sort_field("store"), do: :operation
  defp cache_sort_field("digest"), do: :action_digest
  defp cache_sort_field("latency"), do: :duration_ms
  defp cache_sort_field(_), do: :observed_at

  defp cache_column_patch(path, uri, sort_by, sort_order, column_value) do
    next_order = if sort_by == column_value and sort_order == "desc", do: "asc", else: "desc"

    uri.query
    |> URI.decode_query()
    |> Map.put("cache-sort-by", column_value)
    |> Map.put("cache-sort-order", next_order)
    |> Map.put("page", "1")
    |> URI.encode_query()
    |> then(&"#{path}?#{&1}")
  end

  defp cache_page_patch(path, uri, page), do: "#{path}?#{Query.put(uri.query, "page", to_string(page))}"

  defp invocation_result_label(%{status: "success"}), do: dgettext("dashboard_builds", "Passed")

  defp invocation_result_label(%{command: "build", exit_code: 1}),
    do: dgettext("dashboard_projects", "Build failed (exit code 1)")

  defp invocation_result_label(%{command: "test", exit_code: 1}),
    do: dgettext("dashboard_projects", "Build failed (exit code 1)")

  defp invocation_result_label(%{command: "test", exit_code: 3}),
    do: dgettext("dashboard_projects", "Tests failed or timed out (exit code 3)")

  defp invocation_result_label(%{command: "test", exit_code: 4}),
    do: dgettext("dashboard_projects", "No tests found (exit code 4)")

  defp invocation_result_label(%{exit_code: 2}), do: dgettext("dashboard_projects", "Command-line problem (exit code 2)")

  defp invocation_result_label(%{exit_code: 8}), do: dgettext("dashboard_projects", "Interrupted (exit code 8)")

  defp invocation_result_label(%{exit_code: 32}),
    do: dgettext("dashboard_projects", "External environment failure (exit code 32)")

  defp invocation_result_label(%{exit_code: 33}), do: dgettext("dashboard_projects", "Out of memory (exit code 33)")

  defp invocation_result_label(%{exit_code: 36}),
    do: dgettext("dashboard_projects", "Local environment failure (exit code 36)")

  defp invocation_result_label(%{exit_code: 37}),
    do: dgettext("dashboard_projects", "Internal Bazel error (exit code 37)")

  defp invocation_result_label(%{exit_code: 38}),
    do: dgettext("dashboard_projects", "Result publishing failed (exit code 38)")

  defp invocation_result_label(%{exit_code: 39}),
    do: dgettext("dashboard_projects", "Remote cache entry evicted (exit code 39)")

  defp invocation_result_label(%{exit_code: 45}),
    do: dgettext("dashboard_projects", "Result publishing failed (exit code 45)")

  defp invocation_result_label(%{exit_code: exit_code}),
    do: dgettext("dashboard_projects", "Failed (exit code %{code})", code: exit_code)

  defp invocation_result_badge_color("success"), do: "success"
  defp invocation_result_badge_color(_), do: "destructive"

  defp connected_to_repository?(%{vcs_connection: %{provider: :github}}), do: true
  defp connected_to_repository?(_), do: false

  defp invocation_title(%{target_patterns: []}), do: dgettext("dashboard_projects", "Bazel invocation")
  defp invocation_title(invocation), do: target_patterns_label(invocation.target_patterns)

  defp selected_tab(%{"tab" => tab}) when tab in ["overview", "cache", "timeline", "remote-execution"], do: tab
  defp selected_tab(_params), do: "overview"

  defp load_remote_actions(socket, "remote-execution", invocation, params) do
    page = min(parse_page(params["remote-page"]), 100_000)
    sort_by = if socket.assigns.remote_sort_by == "started-at", do: "start_ms", else: "duration_ms"
    sort_order = socket.assigns.remote_sort_order

    socket
    |> cancel_async(:remote_actions)
    |> assign_async(
      :remote_actions,
      fn ->
        {:ok, result} =
          RecordedSteps.list(invocation, %{
            remote_execution: true,
            page: page,
            sort_by: sort_by,
            sort_order: sort_order
          })

        {:ok, %{remote_actions: Map.put(result, :links, remote_action_links(invocation, result.steps))}}
      end
    )
  end

  defp load_remote_actions(socket, _, _, _), do: cancel_async(socket, :remote_actions)

  # A profile action links to the gateway's record of its execution when its
  # primary output was declared by exactly one recorded execution. Several
  # (retries, or outputs shared by different actions) get no link rather
  # than a guess.
  defp remote_action_links(invocation, steps) do
    outputs = Bazel.profile_primary_outputs(invocation, Enum.map(steps, & &1.id))
    records = Actions.by_output(invocation.project_id, invocation.invocation_id, outputs |> Map.values() |> Enum.uniq())

    for {event_id, output} <- outputs, [{_hash, operation_id}] <- [Map.get(records, output, [])], into: %{} do
      {event_id, operation_id}
    end
  end

  # Pages keep the current sort. Choosing a sort from the dropdown starts at its
  # default order: earliest first for start times, longest first for durations.
  defp remote_path(assigns, page, sort_by \\ nil, sort_order \\ nil) do
    "#{detail_path(assigns)}?" <>
      URI.encode_query(
        Map.reject(
          %{
            "tab" => "remote-execution",
            "remote-page" => page,
            "remote-sort-by" => sort_by || assigns.remote_sort_by,
            "remote-sort-order" => if(sort_by, do: sort_order, else: assigns.remote_sort_order)
          },
          fn {_key, value} -> is_nil(value) end
        )
      )
  end

  # Clicking the active column's header reverses it; another column starts at its default.
  defp remote_header_path(assigns, sort_by) do
    order = remote_sort_order(assigns, sort_by)
    remote_path(assigns, 1, sort_by, order && if(order == "asc", do: "desc", else: "asc"))
  end

  defp remote_sort_order(%{remote_sort_by: sort_by, remote_sort_order: order}, sort_by),
    do: order || if(sort_by == "started-at", do: "asc", else: "desc")

  defp remote_sort_order(_assigns, _sort_by), do: nil

  defp remote_sort_label("started-at"), do: dgettext("dashboard_builds", "Started at")
  defp remote_sort_label(_duration), do: dgettext("dashboard_builds", "Duration")

  defp remote_phases do
    [
      {"queue", :remote_queue_ms, dgettext("dashboard_builds", "Queue")},
      {"input-fetch", :remote_input_fetch_ms, dgettext("dashboard_builds", "Input fetch")},
      {"execution", :remote_execution_ms, dgettext("dashboard_builds", "Execution")},
      {"output-upload", :remote_output_upload_ms, dgettext("dashboard_builds", "Output upload")}
    ]
  end

  # Bar length is relative to the page's longest action. Segments split the
  # action's duration; time outside recorded server phases stays neutral.
  defp trace_rows(%{steps: steps} = result) do
    links = Map.get(result, :links, %{})
    longest = steps |> Enum.map(& &1.duration_ms) |> Enum.max(fn -> 0 end)

    Enum.map(steps, fn action ->
      # Unrecorded phases are left out of the bar and tooltip rather than shown as zero.
      phases =
        for {phase, field, label} <- remote_phases(),
            ms = Map.get(action, field),
            is_number(ms),
            do: %{phase: phase, label: label, ms: ms}

      %{
        action: action,
        operation_id: Map.get(links, action.id),
        width: if(longest > 0, do: max(Float.round((action.duration_ms || 0) / longest * 100, 2), 2), else: 2),
        segments: phase_segments(phases, action.duration_ms || 0),
        phases: phases
      }
    end)
  end

  defp phase_segments(phases, duration) do
    total = max(duration, phases |> Enum.map(& &1.ms) |> Enum.sum())

    for %{phase: phase, ms: ms} <- phases,
        ms > 0 and total > 0,
        do: %{phase: phase, share: Float.round(ms / total * 100, 2)}
  end

  defp remote_duration(nil), do: dgettext("dashboard_builds", "Not recorded")
  defp remote_duration(duration), do: DateFormatter.format_duration_from_milliseconds(duration)

  defp remote_cache_used?(invocation) do
    invocation.cache.hits + invocation.cache.misses + invocation.cache.download_bytes + invocation.cache.upload_bytes > 0
  end

  defp tab_path(assigns, tab), do: "#{detail_path(assigns)}?tab=#{tab}"

  defp remote_action_path(assigns, operation_id),
    do:
      "/#{assigns.selected_account.name}/#{assigns.selected_project.name}/builds/invocations/#{assigns.invocation.invocation_id}/remote-actions/#{operation_id}"

  defp detail_path(assigns),
    do:
      "/#{assigns.selected_account.name}/#{assigns.selected_project.name}/#{assigns.bazel_detail_path}/#{assigns.invocation.invocation_id}"

  defp cache_path(socket, params), do: "#{detail_path(socket.assigns)}?#{URI.encode_query(params)}"
end
