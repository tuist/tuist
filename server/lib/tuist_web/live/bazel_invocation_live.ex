defmodule TuistWeb.BazelInvocationLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.BazelAnalyticsHelpers,
    only: [parse_page: 1, sort_direction: 1, target_patterns_label: 1]

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Helpers.VCSLinks
  import TuistWeb.Runs.RanByBadge

  alias Noora.Filter
  alias Tuist.Bazel
  alias Tuist.ReapiCache
  alias Tuist.Utilities.ByteFormatter
  alias Tuist.Utilities.DateFormatter
  alias Tuist.Utilities.ThroughputFormatter
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  @cache_page_size 20
  @logs_page_size 20
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
         |> assign(
           :has_logs,
           Bazel.invocation_logs_present?(
             project.id,
             invocation_id,
             Bazel.invocation_log_query_options(invocation)
           )
         )
         |> assign(:selected_tab, "overview")
         |> assign(:logs, [])
         |> assign(:log_output, "")
         |> assign(:logs_oldest_sequence_number, nil)
         |> assign(:logs_have_older, false)
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
         |> assign(:critical_path_expanded, false)
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
        raise NotFoundError, dgettext("dashboard_projects", "Bazel invocation not found.")
    end
  end

  def handle_params(params, uri, socket) do
    selected_tab = selected_tab(params)
    project = socket.assigns.selected_project
    invocation = socket.assigns.invocation

    {logs, logs_have_older} =
      if selected_tab == "logs" do
        load_log_tail(project.id, invocation, nil)
      else
        {[], false}
      end

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
     |> assign(:logs, logs)
     |> assign(:log_output, Enum.map_join(logs, "", & &1.message))
     |> assign(:logs_oldest_sequence_number, oldest_log_sequence_number(logs))
     |> assign(:logs_have_older, logs_have_older)
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

  def handle_event("load_older_logs", _params, %{assigns: %{logs_have_older: false}} = socket) do
    {:noreply, socket}
  end

  def handle_event("load_older_logs", _params, socket) do
    %{selected_project: project, invocation: invocation, logs_oldest_sequence_number: before_sequence_number} =
      socket.assigns

    {older_logs, logs_have_older} = load_log_tail(project.id, invocation, before_sequence_number)
    logs = older_logs ++ socket.assigns.logs

    {:noreply,
     socket
     |> assign(:logs, logs)
     |> assign(:log_output, Enum.map_join(logs, "", & &1.message))
     |> assign(:logs_oldest_sequence_number, oldest_log_sequence_number(logs))
     |> assign(:logs_have_older, logs_have_older)}
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
          label={dgettext("dashboard_projects", "Bazel cache")}
          patch={tab_path(assigns, "cache")}
          selected={@selected_tab == "cache"}
        />
        <.tab_menu_horizontal_item
          label={dgettext("dashboard_projects", "Command")}
          patch={tab_path(assigns, "command")}
          selected={@selected_tab == "command"}
        />
        <.tab_menu_horizontal_item
          label={dgettext("dashboard_projects", "Logs")}
          patch={tab_path(assigns, "logs")}
          selected={@selected_tab == "logs"}
        />
      </.tab_menu_horizontal>
      <div :if={@selected_tab == "overview"} data-part="tab-panel">
        <.card title={@bazel_details_title} icon="chart_arcs" data-part="build-details">
          <.card_section data-part="build-details-section">
            <div data-part="metadata-grid">
              <div data-part="metadata-row">
                <div data-part="metadata">
                  <div data-part="title">
                    {dgettext("dashboard_builds", "Status")}
                  </div>
                  <.badge
                    label={invocation_result_label(@invocation)}
                    color={invocation_result_badge_color(@invocation.status)}
                    style="fill"
                    size="large"
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
                <div
                  :if={@invocation.bazel_version != ""}
                  data-part="metadata"
                  data-field="bazel-version"
                >
                  <div data-part="title">{dgettext("dashboard_projects", "Bazel version")}</div>
                  <code data-part="command">{@invocation.bazel_version}</code>
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
            <div
              :if={map_size(@invocation.custom_values || %{}) > 0}
              data-part="custom-metadata-section"
            >
              <span data-part="custom-metadata-label">
                {dgettext("dashboard_builds", "Custom metadata")}
              </span>
              <.table
                id="custom-metadata-table"
                rows={Map.to_list(@invocation.custom_values)}
                row_key={fn {key, _value} -> key end}
              >
                <:col :let={{key, _value}} label={dgettext("dashboard_builds", "Key")}>
                  <.text_cell label={key} />
                </:col>
                <:col :let={{_key, value}} label={dgettext("dashboard_builds", "Value")}>
                  <a
                    :if={url?(value)}
                    href={value}
                    target="_blank"
                    rel="noopener noreferrer"
                    data-part="custom-metadata-link"
                  >
                    {value}
                  </a>
                  <.text_cell :if={not url?(value)} label={value} />
                </:col>
              </.table>
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
      <div :if={@selected_tab == "logs"} data-part="tab-panel">
        <.logs_card
          log_output={@log_output}
          has_logs={@has_logs}
          has_older={@logs_have_older}
        />
      </div>
    </div>
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
            role="list"
            aria-label={dgettext("dashboard_projects", "Build timeline categories")}
          >
            <span
              :for={category <- timeline_categories(@invocation)}
              data-category={category}
              role="listitem"
            >
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
          style={"--timeline-height: #{build_timeline_height(@invocation)}"}
        />
      </.card_section>
    </.card>
    """
  end

  attr :log_output, :string, required: true
  attr :has_logs, :boolean, required: true
  attr :has_older, :boolean, required: true

  def logs_card(assigns) do
    ~H"""
    <.card title={dgettext("dashboard_projects", "Logs")} icon="file_text">
      <.card_section data-part="logs-section">
        <pre :if={@has_logs} data-part="log-output"><code>{@log_output}</code></pre>
        <span :if={not @has_logs} data-part="empty-logs">
          {dgettext("dashboard_projects", "No logs were captured for this invocation.")}
        </span>
        <.button
          :if={@has_older}
          id="bazel-load-older-logs"
          label={dgettext("dashboard_projects", "Load older logs")}
          variant="secondary"
          phx-click="load_older_logs"
        />
      </.card_section>
    </.card>
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
          empty={@cache.hits + @cache.misses == 0}
        />
        <.widget
          id={@widget_id_prefix <> "-downloads"}
          title={dgettext("dashboard_projects", "Cache downloads")}
          description={
            dgettext("dashboard_projects", "Total size of data downloaded from the remote cache.")
          }
          value={ByteFormatter.format_bytes(@cache.download_bytes)}
        />
        <.widget
          id={@widget_id_prefix <> "-uploads"}
          title={dgettext("dashboard_projects", "Cache uploads")}
          description={
            dgettext("dashboard_projects", "Total size of data uploaded to the remote cache.")
          }
          value={ByteFormatter.format_bytes(@cache.upload_bytes)}
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
              <span data-part="value">{@cache.hits + @cache.misses}</span>
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

  attr :invocation, :map, required: true
  attr :project, :map, required: true

  attr :expanded, :boolean, required: true

  def critical_path(assigns) do
    unstyled_actions = critical_path_actions(assigns.invocation)

    longest_action =
      case unstyled_actions do
        [] -> nil
        actions -> Enum.max_by(actions, & &1.duration_ms)
      end

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

    longest_action =
      case actions do
        [] -> nil
        actions -> Enum.max_by(actions, & &1.duration_ms)
      end

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
        <div data-part="critical-path-summary" data-actions-reported={to_string(@actions != [])}>
          <div data-part="critical-path-metric">
            <span data-part="title">{dgettext("dashboard_projects", "Minimum completion time")}</span>
            <strong>{DateFormatter.format_duration_from_milliseconds(@total_duration_ms)}</strong>
          </div>
          <div :if={@actions != []} data-part="critical-path-metric">
            <span data-part="title">{dgettext("dashboard_projects", "Actions on path")}</span>
            <strong>{length(@actions)}</strong>
          </div>
        </div>
        <div :if={@actions != []} data-part="critical-path-breakdown">
          <div data-part="critical-path-breakdown-header">
            <span>{dgettext("dashboard_projects", "Path breakdown")}</span>
            <span>{dgettext("dashboard_projects", "In execution order")}</span>
          </div>
          <div
            data-part="critical-path-timeline"
            role="img"
            aria-label={critical_path_timeline_label(@actions)}
          >
            <span
              :for={action <- @actions}
              data-highlighted={action == @longest_action}
              data-tone={action.tone}
              style={"--action-weight: #{critical_path_timeline_weight(action.duration_ms)}"}
              title={"#{action.display_description} · #{DateFormatter.format_duration_from_milliseconds(action.duration_ms)}"}
            ></span>
          </div>
        </div>
        <div :if={@actions == []} data-part="critical-path-empty">
          <span data-part="title">{dgettext("dashboard_projects", "Action breakdown unavailable")}</span>
          <span data-part="description">
            {dgettext(
              "dashboard_projects",
              "Bazel reported the total critical path, but not its actions."
            )}
          </span>
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
          <div :if={@invocation.bazel_version != ""} data-part="configuration-grid">
            <div :if={@invocation.bazel_version != ""} data-part="configuration">
              <span data-part="title">{dgettext("dashboard_projects", "Bazel version")}</span>
              <code data-part="value">{@invocation.bazel_version}</code>
            </div>
          </div>
          <span :if={@invocation.bazel_version == ""} data-part="empty">
            {dgettext("dashboard_projects", "No configuration details reported")}
          </span>
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
          order_by: [cache_sort_field(cache_sort_by)],
          order_directions: [sort_direction(cache_sort_order)],
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
  defp cache_text_flop_filters(search, _selected_cache_view), do: [%{field: :action_mnemonic, op: :=~, value: search}]

  defp critical_path_present?(invocation),
    do: critical_path_actions(invocation) != [] or Map.get(invocation, :critical_path_duration_ms, 0) > 0

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
              value: [span.lane, span.start_ms, span.start_ms + span.duration_ms],
              name: timeline_span_description(span.description),
              durationLabel: dgettext("dashboard_projects", "Duration"),
              startLabel: dgettext("dashboard_projects", "Started after"),
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
    "#{max(8, 3 + lane_count * 2)}rem"
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

  defp timeline_span_description("loading_and_analysis"), do: dgettext("dashboard_projects", "Loading and analysis")
  defp timeline_span_description(description), do: description

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

  defp critical_path_timeline_label(actions) do
    action_summary =
      Enum.map_join(actions, ", ", fn action ->
        "#{action.display_description}: #{DateFormatter.format_duration_from_milliseconds(action.duration_ms)}"
      end)

    dgettext(
      "dashboard_projects",
      "Critical path duration distribution: %{actions}",
      actions: action_summary
    )
  end

  defp critical_path_action_tone(action, longest_action, _index) when action == longest_action, do: "information"

  defp critical_path_action_tone(_action, _longest_action, _index), do: "neutral"

  defp cache_requests_empty_state?(cache_events, cache_filter, active_cache_filters) do
    Enum.empty?(cache_events) and cache_filter == "" and Enum.empty?(active_cache_filters)
  end

  defp cache_requests_empty_state_title(false, _selected_cache_view),
    do: dgettext("dashboard_projects", "This invocation did not use a remote cache.")

  defp cache_requests_empty_state_title(true, "content-objects"),
    do: dgettext("dashboard_projects", "No content object transfers were observed for this invocation.")

  defp cache_requests_empty_state_title(true, _selected_cache_view),
    do: dgettext("dashboard_projects", "No action cache requests were observed for this invocation.")

  defp cache_hit_rate(%{hit_rate: nil}), do: "0%"
  defp cache_hit_rate(cache), do: "#{cache.hit_rate}%"

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
  defp cache_sort_field("action"), do: :action_mnemonic
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

  defp load_log_tail(project_id, invocation, before_sequence_number) do
    logs =
      Bazel.list_invocation_log_tail(
        project_id,
        invocation.invocation_id,
        before_sequence_number,
        @logs_page_size + 1,
        Bazel.invocation_log_query_options(invocation)
      )

    has_older = length(logs) > @logs_page_size
    {if(has_older, do: Enum.drop(logs, 1), else: logs), has_older}
  end

  defp oldest_log_sequence_number([]), do: nil
  defp oldest_log_sequence_number([log | _logs]), do: log.sequence_number

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

  defp requested_command(invocation), do: Enum.join(["bazel", invocation.command | invocation.target_patterns], " ")

  defp selected_tab(%{"tab" => tab}) when tab in ["overview", "command", "cache", "logs"], do: tab
  defp selected_tab(_params), do: "overview"

  defp remote_cache_used?(invocation) do
    invocation.cache.hits + invocation.cache.misses + invocation.cache.download_bytes + invocation.cache.upload_bytes > 0
  end

  defp tab_path(assigns, tab), do: "#{detail_path(assigns)}?tab=#{tab}"

  defp detail_path(assigns),
    do:
      "/#{assigns.selected_account.name}/#{assigns.selected_project.name}/#{assigns.bazel_detail_path}/#{assigns.invocation.invocation_id}"

  defp cache_path(socket, params), do: "#{detail_path(socket.assigns)}?#{URI.encode_query(params)}"

  defp download_path(%{bazel_detail_path: "builds/invocations"} = assigns) do
    ~p"/#{assigns.selected_account.name}/#{assigns.selected_project.name}/builds/invocations/#{assigns.invocation.invocation_id}/logs/download"
  end

  defp download_path(assigns) do
    ~p"/#{assigns.selected_account.name}/#{assigns.selected_project.name}/invocations/#{assigns.invocation.invocation_id}/logs/download"
  end

  defp url?(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and not is_nil(host) -> true
      _ -> false
    end
  end

  defp url?(_), do: false
end
