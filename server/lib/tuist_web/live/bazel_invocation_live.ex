defmodule TuistWeb.BazelInvocationLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Helpers.VCSLinks

  alias Noora.Filter
  alias Tuist.Bazel
  alias Tuist.ReapiCache
  alias Tuist.Utilities.ByteFormatter
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.CldrHelpers
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  @cache_page_size 20
  @repository_path_regex ~r/(?<![A-Za-z0-9_.\/-])(?!(?:external|bazel-out|bazel-bin|bazel-testlogs|bazel-genfiles)\/)((?:[A-Za-z0-9][A-Za-z0-9_.-]*\/)*(?:[A-Za-z0-9][A-Za-z0-9_.-]*\.[A-Za-z0-9][A-Za-z0-9_.+-]*|BUILD(?:\.bazel)?|WORKSPACE(?:\.bazel)?|MODULE\.bazel))(?![A-Za-z0-9_.\/-])/

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
         |> assign(:has_logs, Bazel.invocation_logs_present?(project.id, invocation_id))
         |> assign(:selected_tab, "overview")
         |> assign(:logs, [])
         |> assign(:log_output, "")
         |> assign(:available_filters, cache_filters())
         |> assign(:cache_events, [])
         |> assign(:cache_timeline_events, [])
         |> assign(:cache_outcome_counts, %{"hit" => 0, "miss" => 0, "write" => 0})
         |> assign(:cache_filter, "")
         |> assign(:active_cache_filters, [])
         |> assign(:cache_current_page, 1)
         |> assign(:cache_total_pages, 0)
         |> assign(:cache_sort_by, "observed")
         |> assign(:cache_sort_order, "desc")
         |> assign(:critical_path_expanded, false)
         |> assign(:bazel_back_label, socket.assigns[:bazel_back_label] || dgettext("dashboard_projects", "Invocations"))
         |> assign(:bazel_back_path, socket.assigns[:bazel_back_path] || "invocations")
         |> assign(:bazel_detail_path, socket.assigns[:bazel_detail_path] || "invocations")
         |> assign(
           :bazel_details_title,
           socket.assigns[:bazel_details_title] || dgettext("dashboard_projects", "Details")
         )
         |> assign(:head_title, "#{title} · #{account.name}/#{project.name} · Tuist")
         |> assign(OpenGraph.og_image_assigns("overview"))}

      {:error, :not_found} ->
        raise NotFoundError, dgettext("dashboard_projects", "Bazel invocation not found.")
    end
  end

  def handle_params(params, uri, socket) do
    selected_tab = selected_tab(params)
    project = socket.assigns.selected_project
    invocation = socket.assigns.invocation

    logs =
      if selected_tab == "logs" do
        Bazel.recent_invocation_logs(project.id, invocation.invocation_id)
      else
        []
      end

    {cache_events, cache_timeline_events, cache_outcome_counts, cache_meta, active_cache_filters, cache_sort_by,
     cache_sort_order} =
      if selected_tab == "cache" do
        load_cache_events(project.id, invocation.invocation_id, params, socket.assigns.available_filters)
      else
        {[], [], %{"hit" => 0, "miss" => 0, "write" => 0}, %{current_page: 1, total_pages: 0}, [], "observed", "desc"}
      end

    {:noreply,
     socket
     |> assign(:selected_tab, selected_tab)
     |> assign(:logs, logs)
     |> assign(:log_output, Enum.map_join(logs, "", & &1.message))
     |> assign(:uri, URI.new!(uri))
     |> assign(:cache_events, cache_events)
     |> assign(:cache_timeline_events, cache_timeline_events)
     |> assign(:cache_outcome_counts, cache_outcome_counts)
     |> assign(:cache_filter, params["cache-filter"] || "")
     |> assign(:cache_current_page, cache_meta.current_page)
     |> assign(:cache_total_pages, cache_meta.total_pages)
     |> assign(:active_cache_filters, active_cache_filters)
     |> assign(:cache_sort_by, cache_sort_by)
     |> assign(:cache_sort_order, cache_sort_order)}
  end

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

  def handle_event("toggle_critical_path", _params, socket) do
    {:noreply, update(socket, :critical_path_expanded, &(not &1))}
  end

  def render(assigns) do
    ~H"""
    <div id="bazel-invocation" class="bazel-invocation">
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
            <.badge
              label={"bazel " <> @invocation.command}
              color="information"
              style="light-fill"
              size="large"
            />
          </div>
        </div>
        <div :if={@has_logs} data-part="actions">
          <.button
            label={dgettext("dashboard_projects", "Download logs")}
            href={download_path(assigns)}
            variant="secondary"
            size="medium"
          >
            <:icon_left><.download /></:icon_left>
          </.button>
        </div>
      </div>
      <.tab_menu_horizontal data-part="tabs">
        <.tab_menu_horizontal_item
          label={dgettext("dashboard_projects", "Overview")}
          patch={tab_path(assigns, "overview")}
          selected={@selected_tab == "overview"}
        />
        <.tab_menu_horizontal_item
          label={dgettext("dashboard_projects", "Command")}
          patch={tab_path(assigns, "command")}
          selected={@selected_tab == "command"}
        />
        <.tab_menu_horizontal_item
          label={dgettext("dashboard_projects", "Cache")}
          patch={tab_path(assigns, "cache")}
          selected={@selected_tab == "cache"}
        />
        <.tab_menu_horizontal_item
          label={dgettext("dashboard_projects", "Logs")}
          patch={tab_path(assigns, "logs")}
          selected={@selected_tab == "logs"}
        />
      </.tab_menu_horizontal>
      <div :if={@selected_tab == "overview"} data-part="tab-panel">
        <.build_metrics invocation={@invocation} />
        <.card title={@bazel_details_title} icon="chart_arcs" data-part="invocation-details-card">
          <.card_section data-part="invocation-details-section">
            <div data-part="metadata-grid">
              <div data-part="metadata-row">
                <div data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_projects", "Result")}</div>
                  <.badge
                    label={invocation_result_label(@invocation)}
                    color={invocation_result_badge_color(@invocation.status)}
                    style="fill"
                    size="large"
                  />
                </div>
                <div data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_projects", "Duration")}</div>
                  <span data-part="label">
                    <.history />
                    {DateFormatter.format_duration_from_milliseconds(@invocation.duration_ms)}
                  </span>
                </div>
                <div data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_projects", "Started")}</div>
                  <span data-part="label">
                    {DateFormatter.format_with_timezone(@invocation.started_at, nil)}
                  </span>
                </div>
                <div data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_projects", "Finished")}</div>
                  <span data-part="label">
                    {DateFormatter.format_with_timezone(@invocation.finished_at, nil)}
                  </span>
                </div>
              </div>
              <div data-part="metadata-row">
                <div data-part="metadata" data-field="targets">
                  <div data-part="title">{dgettext("dashboard_projects", "Targets")}</div>
                  <code data-part="command">{target_patterns_label(@invocation.target_patterns)}</code>
                </div>
                <div
                  :if={@invocation.bazel_version != ""}
                  data-part="metadata"
                  data-field="bazel-version"
                >
                  <div data-part="title">{dgettext("dashboard_projects", "Bazel version")}</div>
                  <code data-part="command">{@invocation.bazel_version}</code>
                </div>
                <div
                  :if={@invocation.compilation_mode != ""}
                  data-part="metadata"
                  data-field="compilation-mode"
                >
                  <div data-part="title">{dgettext("dashboard_projects", "Mode")}</div>
                  <code data-part="command">{@invocation.compilation_mode}</code>
                </div>
                <div
                  :if={@invocation.client_platform != "unknown"}
                  data-part="metadata"
                  data-field="environment"
                >
                  <div data-part="title">{dgettext("dashboard_projects", "Environment")}</div>
                  <span data-part="label">{client_platform_label(@invocation.client_platform)}</span>
                </div>
                <div
                  :if={@invocation.configurations != []}
                  data-part="metadata"
                  data-field="configurations"
                >
                  <div data-part="title">{dgettext("dashboard_projects", "Configurations")}</div>
                  <div data-part="badges">
                    <.badge
                      :for={configuration <- @invocation.configurations}
                      label={configuration}
                      color="information"
                      style="light-fill"
                      size="small"
                    />
                  </div>
                </div>
                <div
                  data-part="metadata"
                  data-field="remote-services"
                  data-configuration-present={to_string(@invocation.configurations != [])}
                >
                  <div data-part="title">{dgettext("dashboard_projects", "Remote services")}</div>
                  <div data-part="badges">
                    <.badge
                      :if={@invocation.remote_cache_enabled}
                      label={dgettext("dashboard_projects", "Remote cache")}
                      color="success"
                      style="light-fill"
                      size="small"
                    />
                    <.badge
                      :if={@invocation.remote_execution_enabled}
                      label={dgettext("dashboard_projects", "Remote execution")}
                      color="success"
                      style="light-fill"
                      size="small"
                    />
                    <.badge
                      :if={
                        not @invocation.remote_cache_enabled and
                          not @invocation.remote_execution_enabled
                      }
                      label={dgettext("dashboard_projects", "Local")}
                      color="neutral"
                      style="light-fill"
                      size="small"
                    />
                  </div>
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
          </.card_section>
        </.card>
        <.build_timeline :if={build_timeline_present?(@invocation)} invocation={@invocation} />
        <.critical_path
          :if={critical_path_present?(@invocation)}
          invocation={@invocation}
          project={@selected_project}
          expanded={@critical_path_expanded}
        />
      </div>
      <div :if={@selected_tab == "command"} data-part="tab-panel">
        <.command_configuration invocation={@invocation} />
      </div>
      <div :if={@selected_tab == "cache"} data-part="tab-panel">
        <.cache_tab
          cache={@invocation.cache}
          cache_events={@cache_events}
          cache_timeline_events={@cache_timeline_events}
          cache_outcome_counts={@cache_outcome_counts}
          cache_filter={@cache_filter}
          active_cache_filters={@active_cache_filters}
          available_filters={@available_filters}
          cache_current_page={@cache_current_page}
          cache_total_pages={@cache_total_pages}
          cache_sort_by={@cache_sort_by}
          cache_sort_order={@cache_sort_order}
          uri={@uri}
          path={detail_path(assigns)}
          remote_cache_enabled={@invocation.remote_cache_enabled}
          table_id="bazel-invocation-cache-events-table"
          filter_id="bazel-invocation-cache-filter-dropdown"
          widget_id_prefix="bazel-invocation-cache"
          search_id="bazel-invocation-cache-search"
        />
      </div>
      <div :if={@selected_tab == "logs"} data-part="tab-panel">
        <.logs_card log_output={@log_output} has_logs={@has_logs} />
      </div>
    </div>
    """
  end

  attr :invocation, :map, required: true

  def build_metrics(assigns) do
    ~H"""
    <.card
      :if={build_metrics_present?(@invocation)}
      title={dgettext("dashboard_projects", "Metrics")}
      icon="chart_bar_popular"
    >
      <.card_section data-part="build-metrics-section">
        <.widget
          id="bazel-processor-time"
          title={dgettext("dashboard_projects", "Processor time")}
          value={DateFormatter.format_duration_from_milliseconds(@invocation.cpu_time_ms)}
          legend_color="primary"
        />
        <.widget
          id="bazel-actions-executed"
          title={dgettext("dashboard_projects", "Actions executed")}
          value={CldrHelpers.format_number(@invocation.actions_executed)}
          legend_color="secondary"
        />
        <.widget
          id="bazel-targets"
          title={dgettext("dashboard_projects", "Targets loaded / configured")}
          value={"#{CldrHelpers.format_number(@invocation.targets_loaded)} / #{CldrHelpers.format_number(@invocation.targets_configured)}"}
          legend_color="tertiary"
        />
        <.widget
          id="bazel-packages-loaded"
          title={dgettext("dashboard_projects", "Packages loaded")}
          value={CldrHelpers.format_number(@invocation.packages_loaded)}
          legend_color="p50"
        />
      </.card_section>
    </.card>
    """
  end

  attr :invocation, :map, required: true

  def build_timeline(assigns) do
    ~H"""
    <.card title={dgettext("dashboard_projects", "Timeline")} icon="chart_bar_popular">
      <.card_section data-part="build-timeline-section">
        <div data-part="build-timeline-header">
          <div
            data-part="legend"
            aria-label={dgettext("dashboard_projects", "Build timeline categories")}
          >
            <span :for={category <- timeline_categories(@invocation)} data-category={category}>
              {timeline_category_label(category)}
            </span>
          </div>
        </div>
        <.chart
          id="bazel-build-timeline"
          type="custom"
          series={build_timeline_series(@invocation)}
          show_legend={false}
          grid_lines
          extra_options={build_timeline_chart_options(@invocation)}
          style={"height: #{build_timeline_height(@invocation)}"}
        />
      </.card_section>
    </.card>
    """
  end

  attr :log_output, :string, required: true
  attr :has_logs, :boolean, required: true

  def logs_card(assigns) do
    ~H"""
    <.card title={dgettext("dashboard_projects", "Logs")} icon="file_text">
      <.card_section data-part="logs-section">
        <pre :if={@has_logs} data-part="log-output"><code>{@log_output}</code></pre>
        <span :if={not @has_logs} data-part="empty-logs">
          {dgettext("dashboard_projects", "No logs were captured for this invocation.")}
        </span>
      </.card_section>
    </.card>
    """
  end

  attr :cache, :map, required: true
  attr :cache_events, :list, required: true
  attr :cache_timeline_events, :list, required: true
  attr :cache_outcome_counts, :map, required: true
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
    <.card title={dgettext("dashboard_projects", "Summary")} icon="database">
      <.card_section data-part="cache-summary-section">
        <.widget
          id={@widget_id_prefix <> "-requests"}
          title={dgettext("dashboard_projects", "Requests")}
          value={cache_request_total(@cache_outcome_counts)}
        />
        <.widget
          id={@widget_id_prefix <> "-hits"}
          title={dgettext("dashboard_projects", "Hits")}
          legend_color="tertiary"
          value={cache_outcome_percentage(@cache_outcome_counts, "hit")}
        />
        <.widget
          id={@widget_id_prefix <> "-misses"}
          title={dgettext("dashboard_projects", "Misses")}
          legend_color="flaky"
          value={cache_outcome_percentage(@cache_outcome_counts, "miss")}
        />
        <.widget
          id={@widget_id_prefix <> "-writes"}
          title={dgettext("dashboard_projects", "Stored")}
          legend_color="secondary"
          value={cache_outcome_percentage(@cache_outcome_counts, "write")}
        />
      </.card_section>
    </.card>
    <.card
      title={dgettext("dashboard_projects", "Requests")}
      icon="server"
      data-part="cache-requests-card"
    >
      <.card_section data-part="cache-requests-section">
        <.empty_card_section
          :if={cache_requests_empty_state?(@cache_events, @cache_filter, @active_cache_filters)}
          title={cache_requests_empty_state_title(@remote_cache_enabled)}
          get_started_href="https://tuist.dev/en/docs/guides/features/cache/bazel-cache"
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
          <div :if={@cache_timeline_events != []} data-part="cache-requests-timeline">
            <div data-part="cache-requests-timeline-header">
              <span data-part="title">{dgettext("dashboard_projects", "Request activity")}</span>
              <div
                data-part="legend"
                aria-label={dgettext("dashboard_projects", "Cache request outcomes")}
              >
                <span data-outcome="hit">{dgettext("dashboard_projects", "Hit")}</span>
                <span data-outcome="miss">{dgettext("dashboard_projects", "Miss")}</span>
                <span data-outcome="write">{dgettext("dashboard_projects", "Stored")}</span>
              </div>
            </div>
            <.chart
              id={@widget_id_prefix <> "-requests-timeline"}
              type="bar"
              series={cache_activity_series(@cache_timeline_events)}
              labels={Enum.map(cache_activity_buckets(@cache_timeline_events), &elem(&1, 0))}
              show_legend={false}
              grid_lines
              stacked
              bar_width={12}
              bar_radius={2}
              extra_options={cache_activity_chart_options()}
              style="height: 9rem"
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
              label={dgettext("dashboard_projects", "Action")}
              patch={cache_column_patch(@path, @uri, @cache_sort_by, @cache_sort_order, "action")}
              sort_order={@cache_sort_by == "action" && @cache_sort_order}
            >
              <.text_cell label={cache_event_action(event)} />
            </:col>
            <:col
              :let={event}
              label={dgettext("dashboard_projects", "Cache")}
              patch={cache_column_patch(@path, @uri, @cache_sort_by, @cache_sort_order, "store")}
              sort_order={@cache_sort_by == "store" && @cache_sort_order}
            >
              <.text_cell label={cache_store_label(event.operation)} />
            </:col>
            <:col
              :let={event}
              label={dgettext("dashboard_projects", "Outcome")}
              patch={cache_column_patch(@path, @uri, @cache_sort_by, @cache_sort_order, "outcome")}
              sort_order={@cache_sort_by == "outcome" && @cache_sort_order}
            >
              <.status_badge_cell
                label={cache_outcome_label(event.outcome)}
                status={cache_outcome_status(event.outcome)}
              />
            </:col>
            <:col
              :let={event}
              label={dgettext("dashboard_projects", "Digest")}
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

  attr :invocation, :map, required: true
  attr :project, :map, required: true

  attr :expanded, :boolean, required: true

  def critical_path(assigns) do
    unstyled_actions = critical_path_actions(assigns.invocation)
    longest_action = Enum.max_by(unstyled_actions, & &1.duration_ms)

    actions =
      unstyled_actions
      |> Enum.with_index(1)
      |> Enum.map(fn {action, index} ->
        description = critical_path_display_description(action.description)
        {description_prefix, source_path, description_suffix} = critical_path_description_parts(description)

        action
        |> Map.put(:tone, critical_path_action_tone(action, longest_action, index))
        |> Map.put(:display_description, description)
        |> Map.put(:description_prefix, description_prefix)
        |> Map.put(:source_path, source_path)
        |> Map.put(:description_suffix, description_suffix)
      end)

    longest_action = Enum.max_by(actions, & &1.duration_ms)
    displayed_actions = if assigns.expanded, do: actions, else: Enum.take(actions, 5)

    total_duration_ms =
      case Map.get(assigns.invocation, :critical_path_duration_ms, 0) do
        duration_ms when duration_ms > 0 -> duration_ms
        _ -> Enum.sum(Enum.map(actions, & &1.duration_ms))
      end

    assigns =
      assigns
      |> assign(:actions, actions)
      |> assign(:displayed_actions, displayed_actions)
      |> assign(:longest_action, longest_action)
      |> assign(:total_duration_ms, total_duration_ms)

    ~H"""
    <.card title={dgettext("dashboard_projects", "Critical path")} icon="git_branch">
      <.card_section data-part="critical-path-section">
        <div data-part="critical-path-summary">
          <div data-part="critical-path-metric">
            <span data-part="title">{dgettext("dashboard_projects", "Minimum completion time")}</span>
            <strong>{DateFormatter.format_duration_from_milliseconds(@total_duration_ms)}</strong>
          </div>
          <div data-part="critical-path-metric">
            <span data-part="title">{dgettext("dashboard_projects", "Actions on path")}</span>
            <strong>{length(@actions)}</strong>
          </div>
        </div>
        <div data-part="critical-path-breakdown">
          <div data-part="critical-path-breakdown-header">
            <span>{dgettext("dashboard_projects", "Path breakdown")}</span>
            <span>{dgettext("dashboard_projects", "In execution order")}</span>
          </div>
          <div
            data-part="critical-path-timeline"
            aria-label={dgettext("dashboard_projects", "Critical path duration distribution")}
          >
            <span
              :for={action <- @actions}
              data-highlighted={action == @longest_action}
              data-tone={action.tone}
              style={"flex-grow: #{critical_path_timeline_weight(action.duration_ms)}"}
              title={"#{action.display_description} · #{DateFormatter.format_duration_from_milliseconds(action.duration_ms)}"}
            ></span>
          </div>
        </div>
        <ol data-part="critical-path-actions">
          <li
            :for={{action, index} <- Enum.with_index(@displayed_actions, 1)}
            data-part="critical-path-action"
            data-highlighted={action == @longest_action}
            data-tone={action.tone}
          >
            <span data-part="critical-path-action-index">{index}</span>
            <span data-part="critical-path-action-description" title={action.description}>
              {action.description_prefix}<.source_file_link
                :if={action.source_path}
                project={@project}
                path={action.source_path}
                commit_sha={@invocation.git_commit_sha}
                branch={@invocation.git_branch}
                fallback_branch={@project.default_branch}
                data-part="source-file"
              />{action.description_suffix}
            </span>
            <span data-part="critical-path-action-share">
              {critical_path_duration_share(action.duration_ms, @total_duration_ms)}
            </span>
            <span data-part="critical-path-action-duration">
              {DateFormatter.format_duration_from_milliseconds(action.duration_ms)}
            </span>
          </li>
        </ol>
        <.button
          :if={length(@actions) > 5}
          label={
            if @expanded,
              do: dgettext("dashboard_projects", "Show fewer actions"),
              else:
                dgettext("dashboard_projects", "Show all %{count} actions", count: length(@actions))
          }
          phx-click="toggle_critical_path"
          variant="secondary"
          size="small"
        />
      </.card_section>
    </.card>
    """
  end

  def command_configuration(assigns) do
    assigns = assign(assigns, :command, requested_command(assigns.invocation))

    ~H"""
    <.card title={dgettext("dashboard_projects", "Command")} icon="settings">
      <.card_section data-part="command-configuration-section">
        <div id="bazel-command-configuration" data-part="command-configuration">
          <div data-part="command-line">
            <span data-part="title">{dgettext("dashboard_projects", "Requested command")}</span>
            <div data-part="command-with-copy">
              <code data-part="command">{@command}</code>
              <.neutral_button
                id="bazel-requested-command-copy"
                size="small"
                phx-hook="Clipboard"
                data-clipboard-value={@command}
                aria-label={dgettext("dashboard_projects", "Copy requested command")}
              >
                <.copy />
              </.neutral_button>
            </div>
          </div>
          <div :if={command_configuration_present?(@invocation)} data-part="configuration-grid">
            <div :if={@invocation.bazel_version != ""} data-part="configuration">
              <span data-part="title">{dgettext("dashboard_projects", "Bazel version")}</span>
              <code data-part="value">{@invocation.bazel_version}</code>
            </div>
            <div :if={@invocation.configurations != []} data-part="configuration">
              <span data-part="title">{dgettext("dashboard_projects", "Configurations")}</span>
              <div data-part="badges">
                <.badge
                  :for={configuration <- @invocation.configurations}
                  label={configuration}
                  color="information"
                  style="light-fill"
                  size="small"
                />
              </div>
            </div>
            <div :if={@invocation.compilation_mode != ""} data-part="configuration">
              <span data-part="title">{dgettext("dashboard_projects", "Compilation mode")}</span>
              <code data-part="value">{@invocation.compilation_mode}</code>
            </div>
            <div
              :if={@invocation.remote_cache_enabled || @invocation.remote_execution_enabled}
              data-part="configuration"
            >
              <span data-part="title">{dgettext("dashboard_projects", "Remote services")}</span>
              <div data-part="badges">
                <.badge
                  :if={@invocation.remote_cache_enabled}
                  label={dgettext("dashboard_projects", "Remote cache")}
                  color="success"
                  style="light-fill"
                  size="small"
                />
                <.badge
                  :if={@invocation.remote_execution_enabled}
                  label={dgettext("dashboard_projects", "Remote execution")}
                  color="success"
                  style="light-fill"
                  size="small"
                />
              </div>
            </div>
          </div>
          <span :if={not command_configuration_present?(@invocation)} data-part="empty">
            {dgettext("dashboard_projects", "No configuration details reported")}
          </span>
          <div :if={command_lines_present?(@invocation)} data-part="command-line-details-list">
            <.command_line_details
              :if={@invocation.original_command_line != []}
              id="bazel-original-command-line"
              title={dgettext("dashboard_projects", "Original Bazel command")}
              description={
                dgettext("dashboard_projects", "What the Bazel client sent to the Bazel server.")
              }
              command_line={@invocation.original_command_line}
            />
            <.command_line_details
              :if={@invocation.canonical_command_line != []}
              id="bazel-resolved-command-line"
              title={dgettext("dashboard_projects", "Resolved Bazel command")}
              description={
                dgettext(
                  "dashboard_projects",
                  "The effective command after .bazelrc and policy expansion."
                )
              }
              command_line={@invocation.canonical_command_line}
            />
            <span data-part="command-redaction-note">
              {dgettext(
                "dashboard_projects",
                "Client environment values and sensitive local settings are omitted or redacted."
              )}
            </span>
          </div>
        </div>
      </.card_section>
    </.card>
    """
  end

  attr(:id, :string, required: true)
  attr(:title, :string, required: true)
  attr(:description, :string, required: true)
  attr(:command_line, :list, required: true)

  def command_line_details(assigns) do
    assigns = assign(assigns, :formatted_command_line, Enum.join(assigns.command_line, " \\\n"))

    ~H"""
    <div id={@id} data-part="command-line-details" phx-hook="NooraCollapsible" data-open="false">
      <div data-part="root">
        <button type="button" data-part="trigger">
          <span data-part="labels">
            <span data-part="title">{@title}</span>
            <span data-part="description">{@description}</span>
          </span>
          <.icon
            id={@id <> "-indicator"}
            name="chevron_down"
            active_name="chevron_up"
            transition="crossfade_rotate"
            active_state="open"
          />
        </button>
        <div data-part="content">
          <code data-part="command">{@formatted_command_line}</code>
        </div>
      </div>
    </div>
    """
  end

  def cache_filters do
    [
      %Filter.Filter{
        id: "operation",
        field: :operation,
        display_name: dgettext("dashboard_projects", "Cache"),
        type: :option,
        options: ["action_cache", "cas"],
        options_display_names: %{
          "action_cache" => dgettext("dashboard_projects", "Action cache"),
          "cas" => dgettext("dashboard_projects", "Content-addressable storage")
        },
        operator: :==,
        value: nil
      },
      %Filter.Filter{
        id: "outcome",
        field: :outcome,
        display_name: dgettext("dashboard_projects", "Outcome"),
        type: :option,
        options: ["hit", "miss", "write"],
        options_display_names: %{
          "hit" => dgettext("dashboard_projects", "Hit"),
          "miss" => dgettext("dashboard_projects", "Miss"),
          "write" => dgettext("dashboard_projects", "Stored")
        },
        operator: :==,
        value: nil
      }
    ]
  end

  defp load_cache_events(project_id, invocation_id, params, available_filters) do
    cache_sort_by = params["cache-sort-by"] || "observed"
    cache_sort_order = params["cache-sort-order"] || "desc"

    active_cache_filters =
      Filter.Operations.decode_filters_from_query(params, available_filters)

    {cache_events, cache_meta} =
      ReapiCache.list_invocation_cache_events(project_id, invocation_id, %{
        filters:
          cache_text_flop_filters(params["cache-filter"]) ++
            Filter.Operations.convert_filters_to_flop(active_cache_filters),
        order_by: [cache_sort_field(cache_sort_by)],
        order_directions: [cache_sort_direction(cache_sort_order)],
        page: parse_cache_page(params["page"]),
        page_size: @cache_page_size
      })

    cache_timeline_events = ReapiCache.list_invocation_cache_timeline_events(project_id, invocation_id)
    cache_outcome_counts = ReapiCache.invocation_cache_outcome_counts(project_id, invocation_id)

    {cache_events, cache_timeline_events, cache_outcome_counts, cache_meta, active_cache_filters, cache_sort_by,
     cache_sort_order}
  end

  defp cache_text_flop_filters(nil), do: []
  defp cache_text_flop_filters(""), do: []
  defp cache_text_flop_filters(search), do: [%{field: :action_mnemonic, op: :like, value: search}]

  defp critical_path_present?(invocation), do: critical_path_actions(invocation) != []

  defp build_metrics_present?(invocation) do
    Enum.any?(
      [
        invocation.cpu_time_ms,
        invocation.actions_executed,
        invocation.targets_loaded,
        invocation.targets_configured,
        invocation.packages_loaded
      ],
      &(&1 > 0)
    )
  end

  defp build_timeline_present?(invocation), do: Map.get(invocation, :build_timeline_span_descriptions, []) != []

  defp build_timeline_series(invocation) do
    [
      %{
        type: "custom",
        name: dgettext("dashboard_projects", "Build activity"),
        renderItem: "fn:rangeBar",
        encode: %{x: [1, 2], y: 0},
        data:
          invocation
          |> build_timeline_spans()
          |> Enum.map(fn span ->
            %{
              value: [span.lane, span.start_ms, span.duration_ms],
              name: span.description,
              category: timeline_category_label(span.category),
              laneLabel: Enum.at(build_timeline_lanes(invocation), span.lane),
              itemStyle: %{color: timeline_category_color(span.category)}
            }
          end)
      }
    ]
  end

  defp build_timeline_chart_options(invocation) do
    %{
      animation: false,
      grid: %{top: 8, right: 16, bottom: 28, left: 32, containLabel: true},
      tooltip: %{trigger: "item", formatter: "fn:rangeBarTooltip"},
      xAxis: %{
        type: "value",
        min: 0,
        max: max(Map.get(invocation, :build_timeline_duration_ms, 0), 1),
        splitNumber: 5,
        axisLabel: %{formatter: "fn:formatMilliseconds"}
      },
      yAxis: %{
        type: "category",
        data: build_timeline_lanes(invocation),
        inverse: true,
        axisLabel: %{fontSize: 11},
        splitLine: %{show: true}
      },
      dataZoom: [%{type: "inside", xAxisIndex: 0, zoomOnMouseWheel: true, moveOnMouseMove: true}]
    }
  end

  defp build_timeline_spans(invocation) do
    [
      Map.get(invocation, :build_timeline_span_lanes, []),
      Map.get(invocation, :build_timeline_span_start_ms, []),
      Map.get(invocation, :build_timeline_span_durations_ms, []),
      Map.get(invocation, :build_timeline_span_categories, []),
      Map.get(invocation, :build_timeline_span_descriptions, [])
    ]
    |> Enum.zip()
    |> Enum.map(fn {lane, start_ms, duration_ms, category, description} ->
      %{lane: lane, start_ms: start_ms, duration_ms: duration_ms, category: category, description: description}
    end)
  end

  defp build_timeline_lanes(invocation), do: Map.get(invocation, :build_timeline_lanes, [])

  defp build_timeline_height(invocation) do
    lane_count = length(build_timeline_lanes(invocation))
    "#{max(12, 4 + lane_count * 2)}rem"
  end

  defp timeline_categories(invocation) do
    invocation
    |> build_timeline_spans()
    |> Enum.map(& &1.category)
    |> Enum.uniq()
    |> Enum.sort_by(&timeline_category_order/1)
  end

  defp timeline_category_order("critical_path"), do: 0
  defp timeline_category_order("execution"), do: 1
  defp timeline_category_order("analysis"), do: 2
  defp timeline_category_order("loading"), do: 3
  defp timeline_category_order("setup"), do: 4
  defp timeline_category_order(_), do: 5

  defp timeline_category_label("critical_path"), do: dgettext("dashboard_projects", "Critical path")
  defp timeline_category_label("execution"), do: dgettext("dashboard_projects", "Execution")
  defp timeline_category_label("analysis"), do: dgettext("dashboard_projects", "Analysis")
  defp timeline_category_label("loading"), do: dgettext("dashboard_projects", "Loading")
  defp timeline_category_label("setup"), do: dgettext("dashboard_projects", "Setup")
  defp timeline_category_label(_), do: dgettext("dashboard_projects", "Other")

  defp timeline_category_color("critical_path"), do: "var:noora-chart-primary"
  defp timeline_category_color("execution"), do: "var:noora-chart-secondary"
  defp timeline_category_color("analysis"), do: "var:noora-chart-tertiary"
  defp timeline_category_color("loading"), do: "var:noora-chart-p50"
  defp timeline_category_color("setup"), do: "var:noora-chart-quaternary"
  defp timeline_category_color(_), do: "var:noora-chart-quaternary"

  defp critical_path_actions(invocation) do
    invocation
    |> Map.get(:critical_path_action_descriptions, [])
    |> Enum.zip(Map.get(invocation, :critical_path_action_durations_ms, []))
    |> Enum.map(fn {description, duration_ms} -> %{description: description, duration_ms: duration_ms} end)
  end

  defp critical_path_display_description("action '" <> description), do: String.trim_trailing(description, "'")

  defp critical_path_display_description(description), do: description

  defp critical_path_description_parts(description) do
    case Regex.run(@repository_path_regex, description) do
      [source_path | _captures] ->
        {start, length} = :binary.match(description, source_path)

        {
          binary_part(description, 0, start),
          source_path,
          binary_part(description, start + length, byte_size(description) - start - length)
        }

      _ ->
        {description, nil, ""}
    end
  end

  defp critical_path_duration_share(_duration_ms, 0), do: "0%"

  defp critical_path_duration_share(duration_ms, total_duration_ms) do
    share = duration_ms / total_duration_ms * 100

    if share > 0 and share < 1, do: "<1%", else: "#{round(share)}%"
  end

  defp critical_path_timeline_weight(duration_ms), do: max(duration_ms, 1)

  defp critical_path_action_tone(action, longest_action, _index) when action == longest_action, do: "information"

  defp critical_path_action_tone(_action, _longest_action, _index), do: "neutral"

  defp cache_requests_empty_state?(cache_events, cache_filter, active_cache_filters) do
    Enum.empty?(cache_events) and cache_filter == "" and Enum.empty?(active_cache_filters)
  end

  defp cache_requests_empty_state_title(true),
    do: dgettext("dashboard_projects", "No cache requests were observed for this invocation.")

  defp cache_requests_empty_state_title(false),
    do: dgettext("dashboard_projects", "This invocation did not use a remote cache.")

  defp cache_request_total(outcome_counts), do: outcome_counts |> Map.values() |> Enum.sum()

  defp cache_outcome_percentage(outcome_counts, outcome) do
    total = cache_request_total(outcome_counts)
    percentage = if total == 0, do: 0.0, else: Map.get(outcome_counts, outcome, 0) / total * 100
    "#{Float.round(percentage, 1)}%"
  end

  defp cache_event_action(%{operation: "cas"}), do: dgettext("dashboard_projects", "Content object")
  defp cache_event_action(%{action_mnemonic: ""}), do: dgettext("dashboard_projects", "Action cache lookup")
  defp cache_event_action(event), do: event.action_mnemonic
  defp cache_store_label("cas"), do: dgettext("dashboard_projects", "Content-addressable storage")
  defp cache_store_label(_), do: dgettext("dashboard_projects", "Action cache")
  defp short_cache_digest(""), do: dgettext("dashboard_projects", "No digest")
  defp short_cache_digest(digest), do: String.slice(digest, 0, 12) <> if(byte_size(digest) > 12, do: "…", else: "")
  defp format_cache_size(0), do: nil
  defp format_cache_size(size), do: ByteFormatter.format_bytes(size)
  defp cache_outcome_label("hit"), do: dgettext("dashboard_projects", "Hit")
  defp cache_outcome_label("miss"), do: dgettext("dashboard_projects", "Miss")
  defp cache_outcome_label(_), do: dgettext("dashboard_projects", "Stored")
  defp cache_outcome_status("hit"), do: "success"
  defp cache_outcome_status("miss"), do: "attention"
  defp cache_outcome_status(_), do: "success"
  defp cache_activity_color("hit"), do: "var:noora-chart-tertiary"
  defp cache_activity_color("miss"), do: "var:noora-chart-flaky"
  defp cache_activity_color(_), do: "var:noora-chart-secondary"

  defp cache_activity_series(events) do
    buckets = cache_activity_buckets(events)

    for outcome <- ["hit", "miss", "write"],
        Enum.any?(events, &(&1.outcome == outcome)) do
      %{
        name: cache_outcome_label(outcome),
        color: cache_activity_color(outcome),
        barMinHeight: 3,
        data: Enum.map(buckets, &cache_activity_bucket_latency(&1, outcome))
      }
    end
  end

  defp cache_activity_buckets(events) do
    events
    |> Enum.group_by(&cache_activity_bucket_timestamp/1)
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp cache_activity_bucket_latency({_timestamp, events}, outcome) do
    outcome_events = Enum.filter(events, &(&1.outcome == outcome))

    if outcome_events == [] do
      nil
    else
      Enum.sum_by(outcome_events, & &1.duration_ms)
    end
  end

  defp cache_activity_chart_options do
    %{
      animation: false,
      grid: %{left: 0, right: 0, top: 4, bottom: 0, containLabel: true},
      tooltip: %{trigger: "item", dateFormat: "minute", valueFormat: "fn:formatMilliseconds"},
      xAxis: %{
        type: "category",
        axisLabel: %{color: "var:noora-surface-label-secondary", formatter: "fn:toLocaleTime"},
        axisLine: %{show: false},
        axisTick: %{show: false},
        splitLine: %{show: false}
      },
      yAxis: %{
        type: "value",
        min: 0,
        minInterval: 1,
        axisLabel: %{color: "var:noora-surface-label-secondary", formatter: "fn:formatMilliseconds"},
        axisLine: %{show: false},
        axisTick: %{show: false},
        splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}}
      }
    }
  end

  defp cache_activity_timestamp(%DateTime{} = observed_at), do: DateTime.to_iso8601(observed_at)
  defp cache_activity_timestamp(%NaiveDateTime{} = observed_at), do: NaiveDateTime.to_iso8601(observed_at) <> "Z"

  defp cache_activity_bucket_timestamp(event) do
    event
    |> Map.fetch!(:observed_at)
    |> cache_activity_timestamp()
    |> String.slice(0, 19)
    |> Kernel.<>("Z")
  end

  defp cache_sort_field("outcome"), do: :outcome
  defp cache_sort_field("action"), do: :action_mnemonic
  defp cache_sort_field("store"), do: :operation
  defp cache_sort_field("digest"), do: :action_digest
  defp cache_sort_field("latency"), do: :duration_ms
  defp cache_sort_field(_), do: :observed_at
  defp cache_sort_direction("asc"), do: :asc
  defp cache_sort_direction(_), do: :desc

  defp parse_cache_page(value) do
    case Integer.parse(value || "1") do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp cache_column_patch(path, uri, sort_by, sort_order, column_value) do
    next_order = if sort_by == column_value and sort_order == "asc", do: "desc", else: "asc"

    uri.query
    |> URI.decode_query()
    |> Map.put("cache-sort-by", column_value)
    |> Map.put("cache-sort-order", next_order)
    |> Map.put("page", "1")
    |> URI.encode_query()
    |> then(&"#{path}?#{&1}")
  end

  defp cache_page_patch(path, uri, page), do: "#{path}?#{Query.put(uri.query, "page", to_string(page))}"

  defp invocation_result_label(%{status: "success"}), do: dgettext("dashboard_projects", "Succeeded")

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

  defp requested_command(%{requested_command: command}) when command != "", do: command
  defp requested_command(invocation), do: Enum.join(["bazel", invocation.command | invocation.target_patterns], " ")

  defp command_lines_present?(invocation),
    do: invocation.original_command_line != [] or invocation.canonical_command_line != []

  defp command_configuration_present?(invocation),
    do:
      invocation.bazel_version != "" or invocation.configurations != [] or invocation.compilation_mode != "" or
        invocation.remote_cache_enabled or invocation.remote_execution_enabled

  defp target_patterns_label([]), do: dgettext("dashboard_projects", "No targets reported")

  defp target_patterns_label([first_target | remaining_targets]) do
    case length(remaining_targets) do
      0 -> first_target
      count -> "#{first_target} +#{count}"
    end
  end

  def client_platform_label("macos_arm64"), do: "macOS · arm64"
  def client_platform_label("macos_x86_64"), do: "macOS · x86_64"
  def client_platform_label("linux_arm64"), do: "Linux · arm64"
  def client_platform_label("linux_x86_64"), do: "Linux · x86_64"
  def client_platform_label(_), do: dgettext("dashboard_projects", "Unknown")

  defp selected_tab(%{"tab" => tab}) when tab in ["overview", "command", "cache", "logs"], do: tab
  defp selected_tab(_params), do: "overview"

  defp tab_path(assigns, tab), do: "#{detail_path(assigns)}?tab=#{tab}"

  defp detail_path(assigns),
    do:
      "/#{assigns.selected_account.name}/#{assigns.selected_project.name}/#{assigns.bazel_detail_path}/#{assigns.invocation.invocation_id}"

  defp cache_path(socket, params), do: "#{detail_path(socket.assigns)}?#{URI.encode_query(params)}"

  defp download_path(assigns),
    do:
      ~p"/#{assigns.selected_account.name}/#{assigns.selected_project.name}/invocations/#{assigns.invocation.invocation_id}/logs/download"
end
