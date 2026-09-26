defmodule TuistWeb.OnceRunLive do
  @moduledoc """
  Detail page for one `once` run. Subscribes to `"once:run:<run_id>"` so
  ingested `ActionCompleted` events append rows and update roll-ups live
  while the run is executing.
  """
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Widget

  alias Noora.Filter
  alias Tuist.OnceEvents
  alias Tuist.Utilities.ByteFormatter
  alias Tuist.Utilities.DateFormatter

  @page_size 50
  @refresh_interval_ms 1_000

  def mount(%{"once_run_id" => run_id}, _session, socket) do
    project = socket.assigns.selected_project

    case OnceEvents.get_run(project.id, run_id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("dashboard_projects", "Run not found"))
         |> push_navigate(
           to: ~p"/#{socket.assigns.selected_account.name}/#{socket.assigns.selected_project.name}/once/build-runs"
         )}

      run ->
        if connected?(socket) do
          OnceEvents.subscribe_run(project.id, run_id)
        end

        {:ok,
         assign(socket,
           run: run,
           available_filters: define_filters(),
           cache: OnceEvents.cache_summary(run),
           cache_detail_metrics: OnceEvents.cache_detail_metrics(run),
           cache_events: [],
           cache_current_page: 1,
           cache_total_pages: 1,
           refresh_scheduled?: false,
           # `handle_params/3` fills these per request, but the render reads
           # them, so they need to exist from the first mount too.
           cache_search: "",
           cache_outcome: nil,
           cache_sort_by: "observed",
           cache_sort_order: "desc"
         )}
    end
  end

  @query_params ~w(
    page search sort_by sort_order
    filter_result_op filter_result_val filter_cache_op filter_cache_val
    cache_view cache_search cache_page cache_outcome cache_sort_by cache_sort_order
  )

  @action_sort_fields ~w(action status cache duration finished)
  @cache_views ~w(actions content-objects)
  @cache_outcomes ~w(hit miss stored reused)
  @cache_sort_fields ~w(action outcome target cache_key size latency observed)

  def handle_params(params, uri, socket) do
    query = Map.take(params, @query_params)
    parsed_uri = URI.parse(uri)

    {:noreply,
     socket
     |> assign(
       run_path: String.trim_trailing(parsed_uri.path, "/cache"),
       uri: parsed_uri,
       query: query,
       active_filters: Filter.Operations.decode_filters_from_query(query, socket.assigns.available_filters),
       search: query["search"] || "",
       sort_by: one_of(query["sort_by"], @action_sort_fields, "action"),
       sort_order: one_of(query["sort_order"], ["desc"], "asc"),
       selected_cache_view: one_of(query["cache_view"], @cache_views, "actions"),
       cache_search: query["cache_search"] || "",
       cache_outcome: one_of(query["cache_outcome"], @cache_outcomes, nil),
       cache_sort_by: one_of(query["cache_sort_by"], @cache_sort_fields, "observed"),
       cache_sort_order: one_of(query["cache_sort_order"], ["asc"], "desc")
     )
     |> load_actions()
     |> load_cache()}
  end

  # Called from the render, where the cache assigns are only present once
  # `handle_params/3` has run, so neither key is assumed.
  defp cache_filters_active?(assigns) do
    Map.get(assigns, :cache_search) not in [nil, ""] or
      not is_nil(Map.get(assigns, :cache_outcome))
  end

  # Actions are only ever a hit or a miss. Offering Stored and Reused on that
  # view left the list unfiltered while every row still read as a match, so
  # each view offers only the outcomes it can actually narrow by.
  defp cache_outcomes_for_view("actions"), do: ~w(hit miss)
  defp cache_outcomes_for_view(_content_objects), do: ~w(hit stored reused)

  # Query strings are user input, so every value that reaches a query has to
  # come back out of a fixed allowlist or fall back to the default.
  defp one_of(value, allowed, default), do: if(value in allowed, do: value, else: default)

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply,
     push_patch(socket,
       to: socket.assigns.run_path <> table_patch(socket.assigns.query, %{"search" => search, "page" => "1"})
     )}
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    query = Filter.Operations.add_filter_to_query(filter_id, socket, socket.assigns.query)

    {:noreply,
     socket
     |> push_patch(to: socket.assigns.run_path <> table_patch(query, %{"page" => "1"}))
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
     |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
  end

  def handle_event("search_cache_events", %{"search" => search}, socket) do
    query = Map.merge(socket.assigns.query, %{"cache_search" => search, "cache_page" => "1"})
    {:noreply, push_patch(socket, to: socket.assigns.run_path <> "/cache?" <> URI.encode_query(query))}
  end

  def handle_event("filter_cache_outcome", %{"outcome" => outcome}, socket) do
    outcome = if outcome == "all", do: nil, else: outcome

    query =
      socket.assigns.query
      |> Map.put("cache_page", "1")
      |> Map.put("cache_outcome", outcome || "")

    {:noreply, push_patch(socket, to: socket.assigns.run_path <> "/cache?" <> URI.encode_query(query))}
  end

  def handle_event("update_filter", params, socket) do
    query = Filter.Operations.update_filters_in_query(params, socket, socket.assigns.query)

    {:noreply,
     socket
     |> push_patch(to: socket.assigns.run_path <> table_patch(query, %{"page" => "1"}))
     |> push_event("close-dropdown", %{id: "all", all: true})
     |> push_event("close-popover", %{id: "all", all: true})}
  end

  # The run topic also carries `:test_case_ingested` and `:test_suite_ingested`,
  # and a `once test` run reaches this page too, so a narrow match crash-looped
  # the LiveView on the first streamed case.
  #
  # Reloading on every broadcast also meant the run, the actions page and count
  # and the whole cache tab were re-queried per event, with system samples
  # arriving every second. Refreshes coalesce to one a second, the way
  # `OnceTestRunLive` already does.
  def handle_info({event, _}, socket)
      when event in [
             :action_ingested,
             :run_updated,
             :cache_event_ingested,
             :system_sampled,
             :test_case_ingested,
             :test_suite_ingested
           ] do
    schedule_refresh(socket)
  end

  def handle_info(:refresh, socket) do
    run = OnceEvents.get_run(socket.assigns.selected_project.id, socket.assigns.run.run_id)

    {:noreply,
     socket
     |> assign(:run, run || socket.assigns.run)
     |> assign(:refresh_scheduled?, false)
     |> load_actions()
     |> load_cache()}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp schedule_refresh(%{assigns: %{refresh_scheduled?: true}} = socket), do: {:noreply, socket}

  defp schedule_refresh(socket) do
    Process.send_after(self(), :refresh, @refresh_interval_ms)
    {:noreply, assign(socket, :refresh_scheduled?, true)}
  end

  def render(assigns) do
    ~H"""
    <div id="once-run" class="once-run">
      <.button
        label={dgettext("dashboard_projects", "Build Runs")}
        data-part="back-button"
        variant="secondary"
        size="medium"
        navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/once/build-runs"}
      >
        <:icon_left><.icon name="arrow_left" /></:icon_left>
      </.button>
      <div data-part="header">
        <div data-part="title-group">
          <div data-part="title">
            <div
              :if={@run.finalization == "finalized" and @run.exit_status == 0}
              data-part="badge-success"
            >
              <div data-part="icon"><.circle_check /></div>
            </div>
            <div
              :if={@run.finalization == "finalized" and @run.exit_status not in [nil, 0]}
              data-part="badge-failure"
            >
              <div data-part="icon"><.alert_circle /></div>
            </div>
            <div :if={@run.finalization != "finalized"} data-part="badge-processing">
              <div data-part="icon"><.circle_dashed /></div>
            </div>
            <h1 data-part="label">{run_title(@run)}</h1>
          </div>
        </div>
      </div>
      <.tab_menu_horizontal>
        <.tab_menu_horizontal_item
          label={dgettext("dashboard_projects", "Overview")}
          selected={@live_action == :overview}
          patch={~p"/#{@selected_account.name}/#{@selected_project.name}/once/runs/#{@run.run_id}"}
        />
        <.tab_menu_horizontal_item
          label={dgettext("dashboard_projects", "Once Cache")}
          selected={@live_action == :cache}
          patch={
            ~p"/#{@selected_account.name}/#{@selected_project.name}/once/runs/#{@run.run_id}/cache"
          }
        />
      </.tab_menu_horizontal>
      <.once_cache_tab
        :if={@live_action == :cache}
        run={@run}
        cache={@cache}
        cache_detail_metrics={@cache_detail_metrics}
        cache_events={@cache_events}
        selected_cache_view={@selected_cache_view}
        cache_search={@cache_search}
        cache_outcome={@cache_outcome}
        cache_sort_by={@cache_sort_by}
        cache_sort_order={@cache_sort_order}
        cache_current_page={@cache_current_page}
        cache_total_pages={@cache_total_pages}
        uri={@uri}
        path={@run_path}
      />
      <div :if={@live_action == :overview}>
        <.card
          title={dgettext("dashboard_builds", "Build Details")}
          icon="chart_arcs"
          data-part="build-details"
        >
          <.card_section data-part="build-details-section">
            <div data-part="metadata-grid">
              <div data-part="metadata-row">
                <div data-part="metadata" data-field="command">
                  <div data-part="title">{dgettext("dashboard_builds", "Command")}</div>
                  <span data-part="command-label">{command_display(@run)}</span>
                  <span :if={redacted_command?(@run)} data-part="command-note">
                    {dgettext(
                      "dashboard_projects",
                      "Argument values are redacted by Once before this command is sent to Tuist."
                    )}
                  </span>
                </div>
              </div>

              <div data-part="metadata-row">
                <div data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_builds", "Status")}</div>
                  <.badge
                    label={run_status_label(@run)}
                    color={run_status_badge_color(@run)}
                    style="fill"
                    size="large"
                  />
                </div>
                <div data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_projects", "Kind")}</div>
                  <.badge label={kind_label(@run.kind)} color="primary" style="fill" size="large" />
                </div>
                <div data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_builds", "Build duration")}</div>
                  <span data-part="label">
                    <.history /> {format_duration_ms(@run.wall_ms)}
                  </span>
                </div>
                <div data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_builds", "Built at")}</div>
                  <span data-part="label">{DateFormatter.format_with_timezone(
                    @run.started_at,
                    @user_timezone
                  )}</span>
                </div>
              </div>

              <div data-part="metadata-row">
                <div data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_projects", "Actions")}</div>
                  <span data-part="label">{format_number(@run.total_actions)}</span>
                </div>
                <div data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_projects", "Cache hits")}</div>
                  <span data-part="label">{format_number(@run.cached_actions)}</span>
                </div>
                <div data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_projects", "Executed")}</div>
                  <span data-part="label">{format_number(@run.executed_actions)}</span>
                </div>
                <div data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_projects", "Failed")}</div>
                  <span data-part="label">{format_number(@run.failed_actions)}</span>
                </div>
              </div>

              <div data-part="metadata-row">
                <div :if={git_rev_present?(@run)} data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_projects", "Commit")}</div>
                  <span data-part="label"><.git_commit />{git_short_sha(@run.git_rev)}</span>
                </div>
                <div :if={host_class_present?(@run)} data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_projects", "Host")}</div>
                  <span data-part="label">{@run.host_class}</span>
                </div>
                <div :if={once_version_present?(@run)} data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_projects", "Once version")}</div>
                  <span data-part="label">{@run.once_version}</span>
                </div>
                <div data-part="metadata">
                  <div data-part="title">{dgettext("dashboard_projects", "Run identifier")}</div>
                  <span data-part="label">{@run.run_id}</span>
                </div>
              </div>
            </div>
          </.card_section>
        </.card>

        <.card
          title={dgettext("dashboard_projects", "Actions")}
          icon="subtask"
          data-part="once-actions-card"
        >
          <.card_section data-part="once-actions-section">
            <div data-part="filters">
              <.form for={%{}} id="once-actions-search-form" phx-change="search" phx-submit="search">
                <.text_input
                  type="search"
                  id="once-actions-search"
                  name="search"
                  placeholder={dgettext("dashboard_projects", "Search actions or targets...")}
                  show_suffix={false}
                  value={@search}
                  phx-debounce="200"
                />
              </.form>
              <.filter_dropdown
                id="once-actions-filter-dropdown"
                label={dgettext("dashboard_projects", "Filter")}
                available_filters={@available_filters}
                active_filters={@active_filters}
              />
            </div>
            <div :if={Enum.any?(@active_filters)} data-part="active-filters">
              <.active_filter :for={filter <- @active_filters} filter={filter} />
            </div>
            <div :if={Enum.any?(@actions)} data-part="once-actions-table">
              <.table id="once-actions-table" rows={@actions} row_key={& &1.id}>
                <:col
                  :let={action}
                  label={dgettext("dashboard_projects", "Action")}
                  patch={column_patch(assigns, "action")}
                  sort_order={@sort_by == "action" && @sort_order}
                >
                  <.text_and_description_cell
                    label={action_label(action)}
                    description={action.target_execution_id}
                  />
                </:col>
                <:col
                  :let={action}
                  label={dgettext("dashboard_projects", "Status")}
                  patch={column_patch(assigns, "status")}
                  sort_order={@sort_by == "status" && @sort_order}
                >
                  <.status_badge_cell
                    label={action_status_label(action.result)}
                    status={action_status_variant(action)}
                  />
                </:col>
                <:col
                  :let={action}
                  label={dgettext("dashboard_projects", "Cache")}
                  patch={column_patch(assigns, "cache")}
                  sort_order={@sort_by == "cache" && @sort_order}
                >
                  <.badge_cell
                    label={
                      if action.was_cached,
                        do: dgettext("dashboard_projects", "Hit"),
                        else: dgettext("dashboard_projects", "Miss")
                    }
                    color={if action.was_cached, do: "success", else: "neutral"}
                  />
                </:col>
                <:col
                  :let={action}
                  label={dgettext("dashboard_projects", "Duration")}
                  patch={column_patch(assigns, "duration")}
                  sort_order={@sort_by == "duration" && @sort_order}
                >
                  <.text_cell label={format_duration_ms(action.duration_ms)} icon="history" />
                </:col>
                <:col
                  :let={action}
                  label={dgettext("dashboard_projects", "Finished")}
                  patch={column_patch(assigns, "finished")}
                  sort_order={@sort_by == "finished" && @sort_order}
                >
                  <.text_cell label={
                    DateFormatter.format_with_timezone(action.finished_at, @user_timezone)
                  } />
                </:col>
              </.table>
              <.pagination_group
                :if={@total_pages > 1}
                current_page={@page}
                number_of_pages={@total_pages}
                page_patch={&table_patch(@query, %{"page" => to_string(&1)})}
              />
            </div>
            <.empty_card_section
              :if={Enum.empty?(@actions)}
              title={empty_title(assigns)}
            >
              <:image>
                <img
                  src={~p"/images/empty_line_chart_light.png"}
                  data-theme="light"
                  loading="lazy"
                  decoding="async"
                />
                <img
                  src={~p"/images/empty_line_chart_dark.png"}
                  data-theme="dark"
                  loading="lazy"
                  decoding="async"
                />
              </:image>
            </.empty_card_section>
          </.card_section>
        </.card>
      </div>
    </div>
    """
  end

  attr :run, :map, required: true
  attr :cache, :map, required: true
  attr :cache_detail_metrics, :map, required: true
  attr :cache_events, :list, required: true
  attr :selected_cache_view, :string, required: true
  attr :cache_search, :string, required: true
  attr :cache_outcome, :string, default: nil
  attr :cache_sort_by, :string, default: "observed"
  attr :cache_sort_order, :string, default: "desc"
  attr :cache_current_page, :integer, required: true
  attr :cache_total_pages, :integer, required: true
  attr :uri, :map, required: true
  attr :path, :string, required: true

  def once_cache_tab(assigns) do
    ~H"""
    <.card
      title={dgettext("dashboard_projects", "Cache Summary")}
      icon="chart_arcs"
      data-part="cache-summary-card"
    >
      <.card_section data-part="cache-summary-section">
        <.widget
          id="once-cache-action-hits"
          title={dgettext("dashboard_projects", "Action hits")}
          description={
            dgettext(
              "dashboard_projects",
              "Actions that replayed from the Once cache instead of executing."
            )
          }
          value={@cache.hits}
          empty={cache_summary_empty?(@cache)}
        />
        <.widget
          id="once-cache-action-misses"
          title={dgettext("dashboard_projects", "Action misses")}
          description={
            dgettext(
              "dashboard_projects",
              "Actions that had to execute because the Once cache had no result."
            )
          }
          value={@cache.misses}
          empty={cache_summary_empty?(@cache)}
        />
        <.widget
          id="once-cache-hit-rate"
          title={dgettext("dashboard_projects", "Hit rate")}
          description={
            dgettext(
              "dashboard_projects",
              "Fraction of the run's actions that replayed from the cache."
            )
          }
          value={format_hit_rate(@cache.hit_rate)}
          empty={is_nil(@cache.hit_rate)}
        />
        <.widget
          id="once-cache-downloads"
          title={dgettext("dashboard_projects", "Content downloaded")}
          description={
            dgettext(
              "dashboard_projects",
              "Total bytes moved from the Once cache into this run."
            )
          }
          value={ByteFormatter.format_bytes(@cache.content_download_bytes)}
          empty={cache_summary_empty?(@cache)}
        />
        <.widget
          id="once-cache-uploads"
          title={dgettext("dashboard_projects", "Content uploaded")}
          description={
            dgettext(
              "dashboard_projects",
              "Total bytes this run stored back into the Once cache."
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
        patch={cache_view_patch(@path, "actions", @cache_search)}
      />
      <.tab_menu_horizontal_item
        label={dgettext("dashboard_projects", "Content Objects")}
        selected={@selected_cache_view == "content-objects"}
        patch={cache_view_patch(@path, "content-objects", @cache_search)}
      />
    </.tab_menu_horizontal>
    <.card
      title={dgettext("dashboard_projects", "Once Cache")}
      icon="database"
      data-part="cache-requests-card"
    >
      <.card_section data-part="bazel-cache-card-section">
        <.empty_card_section
          :if={@cache_events == [] and not cache_filters_active?(assigns)}
          title={
            if @selected_cache_view == "actions",
              do: dgettext("dashboard_projects", "No cache lookups reported yet"),
              else: dgettext("dashboard_projects", "No content transfers reported yet")
          }
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
          :if={@cache_events != [] or cache_filters_active?(assigns)}
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
              id="once-cache-actions-breakdown"
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
              id="once-cache-content-breakdown"
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
              id="once-cache-read-latency"
              title={dgettext("dashboard_projects", "Avg. latency reading cache keys")}
              description={
                dgettext(
                  "dashboard_projects",
                  "Time Once spent reading action cache keys, including hits and misses."
                )
              }
              value={
                DateFormatter.format_duration_from_milliseconds(
                  @cache_detail_metrics.action_read_latency_ms
                )
              }
              empty={cache_summary_empty?(@cache)}
            />
            <.widget
              id="once-cache-write-latency"
              title={dgettext("dashboard_projects", "Avg. latency writing cache keys")}
              description={
                dgettext(
                  "dashboard_projects",
                  "Time Once spent writing action results back into the cache."
                )
              }
              value={
                DateFormatter.format_duration_from_milliseconds(
                  @cache_detail_metrics.action_write_latency_ms
                )
              }
              empty={cache_summary_empty?(@cache)}
            />
          </div>
          <div :if={@selected_cache_view == "content-objects"} data-part="throughput-widgets">
            <.widget
              id="once-cache-download-throughput"
              title={dgettext("dashboard_projects", "Download throughput")}
              description={
                dgettext("dashboard_projects", "Average throughput for downloaded content objects.")
              }
              value={
                format_throughput(@cache_detail_metrics.content_download_throughput_bytes_per_second)
              }
              empty={cache_summary_empty?(@cache)}
            />
            <.widget
              id="once-cache-upload-throughput"
              title={dgettext("dashboard_projects", "Upload throughput")}
              description={
                dgettext("dashboard_projects", "Average throughput for uploaded content objects.")
              }
              value={
                format_throughput(@cache_detail_metrics.content_upload_throughput_bytes_per_second)
              }
              empty={cache_summary_empty?(@cache)}
            />
          </div>
          <div data-part="filters">
            <.form
              id="once-cache-search-form"
              for={%{}}
              phx-change="search_cache_events"
              phx-debounce="200"
            >
              <.text_input
                type="search"
                id="once-cache-search"
                name="search"
                placeholder={dgettext("dashboard_builds", "Search...")}
                show_suffix={false}
                data-part="search"
                value={@cache_search}
              />
            </.form>
            <.dropdown
              id="once-cache-filter-dropdown"
              label={dgettext("dashboard_projects", "Filter")}
            >
              <:icon><.icon name="filter" /></:icon>
              <.dropdown_item
                :for={outcome <- cache_outcomes_for_view(@selected_cache_view)}
                value={outcome}
                label={cache_outcome_display_name(outcome)}
                phx-click="filter_cache_outcome"
                phx-value-outcome={outcome}
              />
              <.dropdown_item
                value="all"
                label={dgettext("dashboard_projects", "All outcomes")}
                phx-click="filter_cache_outcome"
                phx-value-outcome="all"
              />
            </.dropdown>
          </div>
          <.empty_card_section
            :if={@cache_events == []}
            title={dgettext("dashboard_projects", "No cache activity matches your search or filters")}
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
          <.table :if={@cache_events != []} id="once-cache-table" rows={@cache_events}>
            <:col
              :let={event}
              :if={@selected_cache_view == "actions"}
              label={dgettext("dashboard_projects", "Action")}
            >
              <.text_cell label={event_action_label(event)} />
            </:col>
            <:col
              :let={event}
              :if={@selected_cache_view == "content-objects"}
              label={dgettext("dashboard_projects", "Key")}
            >
              <.text_cell label={truncate_hash(event.content_hash)} title={event.content_hash} />
            </:col>
            <:col :let={event} label={cache_status_column_label(@selected_cache_view)}>
              <.status_badge_cell
                label={cache_outcome_label(event, @selected_cache_view)}
                status={event_outcome_status(event)}
              />
            </:col>
            <:col
              :let={event}
              :if={@selected_cache_view == "actions"}
              label={dgettext("dashboard_projects", "Target")}
            >
              <.text_cell label={event.target_execution_id || "—"} />
            </:col>
            <:col
              :let={event}
              :if={@selected_cache_view == "actions"}
              label={dgettext("dashboard_projects", "Cache key")}
            >
              <.text_cell
                label={truncate_hash(event.content_hash)}
                title={event.content_hash}
                sublabel={
                  if event.content_size_bytes > 0,
                    do: ByteFormatter.format_bytes(event.content_size_bytes),
                    else: nil
                }
              />
            </:col>
            <:col
              :let={event}
              :if={@selected_cache_view == "content-objects"}
              label={dgettext("dashboard_projects", "Size")}
            >
              <.text_cell label={ByteFormatter.format_bytes(event.content_size_bytes || 0)} />
            </:col>
            <:col :let={event} label={dgettext("dashboard_projects", "Latency")}>
              <.text_cell
                label={DateFormatter.format_duration_from_milliseconds(event.duration_ms || 0)}
                icon="history"
              />
            </:col>
            <:col :let={event} label={dgettext("dashboard_projects", "Observed")}>
              <.text_cell label={DateFormatter.from_now(event.observed_at)} />
            </:col>
          </.table>
          <.pagination_group
            :if={@cache_events != [] and @cache_total_pages > 1}
            current_page={@cache_current_page}
            number_of_pages={@cache_total_pages}
            page_patch={
              fn page ->
                cache_page_patch(
                  @path,
                  @selected_cache_view,
                  @cache_search,
                  page,
                  @cache_outcome,
                  @cache_sort_by,
                  @cache_sort_order
                )
              end
            }
            data-part="cache-pagination"
          />
        </div>
      </.card_section>
    </.card>
    """
  end

  defp cache_summary_empty?(%{hits: 0, misses: 0, content_download_bytes: 0, content_upload_bytes: 0}), do: true
  defp cache_summary_empty?(_), do: false

  defp format_hit_rate(nil), do: "—"
  defp format_hit_rate(rate) when is_float(rate), do: "#{:erlang.float_to_binary(rate, decimals: 1)}%"
  defp format_hit_rate(rate), do: "#{rate}%"

  defp cache_view_patch(path, view, search) do
    query = URI.encode_query(%{"cache_view" => view, "cache_search" => search})
    path <> "/cache?" <> query
  end

  defp event_action_label(%{action_identifier: identifier}) when is_binary(identifier) and identifier != "" do
    action_mnemonic(identifier)
  end

  defp event_action_label(%{kind: "upload"}), do: dgettext("dashboard_projects", "Upload")
  defp event_action_label(%{kind: "download"}), do: dgettext("dashboard_projects", "Download")
  defp event_action_label(%{kind: "reused"}), do: dgettext("dashboard_projects", "Reused")
  defp event_action_label(_), do: dgettext("dashboard_projects", "Cache")

  # Once identifiers land in one of two shapes:
  #   1. Buck2-style `<label-id>:<action-name>`, where the action
  #      name is what the Rust prelude declares (`rustc`,
  #      `build-script`, `build-script-rustc`, `link`, and a few
  #      materialization actions).
  #   2. Ecosystem-parsed `<verb> <target> v<version>` (`rustc
  #      addr2line v0.24.2`, `link mise`, `compile build.rs (…)`).
  # Extract the mnemonic verb from either shape so the Action column
  # reads like Bazel's (Rustc, Link, Build-script).
  defp action_mnemonic("compile build.rs" <> _), do: dgettext("dashboard_projects", "Build script")

  defp action_mnemonic(identifier) do
    case String.split(identifier, ":", parts: 2) do
      [_, action_name] -> action_name |> String.trim() |> mnemonic_from_action_name()
      [only] -> only |> String.split(" ", parts: 2) |> List.first() |> capitalize_mnemonic()
    end
  end

  # For Buck2-style names the action verb may still carry a suffix
  # after a slash or dot (`.once/out/<crate>/source`, `materialize/dir`).
  # Take the first path segment and capitalize it.
  defp mnemonic_from_action_name(name) do
    name
    |> String.trim_leading(".")
    |> String.split(["/", "\\"], parts: 2)
    |> List.first()
    |> capitalize_mnemonic()
  end

  defp capitalize_mnemonic(""), do: dgettext("dashboard_projects", "Action")

  defp capitalize_mnemonic("rustc"), do: "Rustc"
  defp capitalize_mnemonic("build-script"), do: "Build script"
  defp capitalize_mnemonic("build-script-rustc"), do: "Build script (rustc)"
  defp capitalize_mnemonic("link"), do: "Link"
  defp capitalize_mnemonic("once"), do: "Materialize"
  defp capitalize_mnemonic("materialize_host_tree"), do: "Materialize"

  defp capitalize_mnemonic(word) do
    word
    |> String.replace("_", " ")
    |> String.replace("-", " ")
    |> String.capitalize()
  end

  defp cache_outcome_display_name("hit"), do: dgettext("dashboard_projects", "Hit")
  defp cache_outcome_display_name("miss"), do: dgettext("dashboard_projects", "Missed")
  defp cache_outcome_display_name("stored"), do: dgettext("dashboard_projects", "Stored")
  defp cache_outcome_display_name("reused"), do: dgettext("dashboard_projects", "Reused")
  defp cache_outcome_display_name(other), do: other

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

  # Content-objects equivalent of `cache_action_breakdown_series/1`:
  # split the bar into Download / Upload using the same rounded outer
  # corners the Bazel breakdown uses, so both pages render an
  # identical Content objects chip.
  defp cache_content_breakdown_series(metrics) do
    downloads = metrics.content_download_count || 0
    uploads = metrics.content_upload_count || 0

    [
      %{
        name: dgettext("dashboard_projects", "Download"),
        type: "bar",
        stack: "total",
        emphasis: %{focus: "series"},
        data: [downloads],
        color: "var:hits-chart-legend-remote",
        itemStyle: %{borderRadius: cache_breakdown_border_radius(downloads, uploads, :first)}
      },
      %{
        name: dgettext("dashboard_projects", "Upload"),
        type: "bar",
        stack: "total",
        emphasis: %{focus: "series"},
        data: [uploads],
        color: "var:hits-chart-legend-local",
        itemStyle: %{borderRadius: cache_breakdown_border_radius(downloads, uploads, :second)}
      }
    ]
  end

  # Column header + badge label swap between the two views: the
  # Cacheable Actions table lives on hit/miss (a boolean-ish state),
  # so the column is "Hit" and the badge reads Hit/Missed. The
  # Content Objects table lives on transfer direction, so the column
  # is "Status" and the badge reads Download/Upload.
  defp cache_status_column_label("content-objects"), do: dgettext("dashboard_projects", "Status")

  defp cache_status_column_label(_), do: dgettext("dashboard_projects", "Hit")

  defp cache_outcome_label(event, "content-objects") do
    case event.outcome do
      "hit" -> dgettext("dashboard_projects", "Download")
      "stored" -> dgettext("dashboard_projects", "Upload")
      _ -> event_outcome_label(event)
    end
  end

  defp cache_outcome_label(event, _), do: event_outcome_label(event)

  # Bytes/second → human-readable Mbps/Kbps for the throughput
  # widgets. Bazel uses `TuistWeb.Utilities.ThroughputFormatter` for
  # the same purpose; we inline a tiny formatter to avoid dragging
  # that helper into scope for a two-line function.
  defp format_throughput(nil), do: "0 B/s"
  defp format_throughput(bytes_per_second) when bytes_per_second <= 0, do: "0 B/s"

  defp format_throughput(bytes_per_second) when is_number(bytes_per_second) do
    bits = bytes_per_second * 8

    cond do
      bits >= 1_000_000_000 -> "#{Float.round(bits / 1_000_000_000, 1)} Gbps"
      bits >= 1_000_000 -> "#{Float.round(bits / 1_000_000, 1)} Mbps"
      bits >= 1_000 -> "#{Float.round(bits / 1_000, 1)} Kbps"
      true -> "#{round(bits)} bps"
    end
  end

  # Mirror of Bazel's cache-breakdown chart options so the two pages
  # render identical bars: rounded outer corners, thin legend chip,
  # 62px chart height picked up by the shared card_section CSS.
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

  # `borderRadius` on the two stacked segments: rounded on the outer
  # edges only, flat where they meet in the middle. A single-value
  # bar rounds all four corners; an empty segment stays square so it
  # renders as nothing at all.
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

  defp cache_page_patch(path, view, search, page, outcome, sort_by, sort_order) do
    query =
      URI.encode_query(%{
        "cache_view" => view,
        "cache_search" => search,
        "cache_outcome" => outcome || "",
        "cache_sort_by" => sort_by || "",
        "cache_sort_order" => sort_order || "",
        "cache_page" => Integer.to_string(page)
      })

    path <> "/cache?" <> query
  end

  defp event_outcome_label(%{outcome: "hit"}), do: dgettext("dashboard_projects", "Hit")
  defp event_outcome_label(%{outcome: "miss"}), do: dgettext("dashboard_projects", "Missed")
  defp event_outcome_label(%{outcome: "stored"}), do: dgettext("dashboard_projects", "Stored")
  defp event_outcome_label(%{outcome: "reused"}), do: dgettext("dashboard_projects", "Reused")
  defp event_outcome_label(_), do: "—"

  defp event_outcome_status(%{outcome: outcome}) when outcome in ["hit", "stored", "reused"], do: "success"
  defp event_outcome_status(%{outcome: "miss"}), do: "warning"
  defp event_outcome_status(_), do: "information"

  defp truncate_hash(nil), do: "—"
  defp truncate_hash(hash) when byte_size(hash) <= 12, do: hash
  defp truncate_hash(hash), do: binary_part(hash, 0, 12) <> "…"

  defp load_cache(socket) do
    assigns = socket.assigns
    run = assigns.run
    view = assigns.selected_cache_view
    search = assigns.cache_search
    outcome = assigns.cache_outcome

    total = OnceEvents.count_cache_events(run, view: view, search: search, outcome: outcome)
    total_pages = max(1, div(total + @page_size - 1, @page_size))

    page =
      case Integer.parse(assigns.query["cache_page"] || "1") do
        {page, ""} when page > 0 -> min(page, total_pages)
        _ -> 1
      end

    events =
      OnceEvents.list_cache_events(run,
        view: view,
        search: search,
        outcome: outcome,
        sort_by: assigns.cache_sort_by,
        sort_order: assigns.cache_sort_order,
        limit: @page_size,
        offset: (page - 1) * @page_size
      )

    assign(socket,
      cache: OnceEvents.cache_summary(run),
      cache_detail_metrics: OnceEvents.cache_detail_metrics(run),
      cache_events: events,
      cache_current_page: page,
      cache_total_pages: total_pages
    )
  end

  defp load_actions(socket) do
    assigns = socket.assigns

    opts = [
      search: assigns.search,
      filters: Filter.Operations.convert_filters_to_flop(assigns.active_filters),
      sort_by: assigns.sort_by,
      sort_order: assigns.sort_order
    ]

    count = OnceEvents.count_actions(assigns.run, opts)
    total_pages = max(1, div(count + @page_size - 1, @page_size))

    page =
      case Integer.parse(assigns.query["page"] || "1") do
        {page, ""} when page > 0 -> min(page, total_pages)
        _ -> 1
      end

    actions = OnceEvents.list_actions(assigns.run, opts ++ [limit: @page_size, offset: (page - 1) * @page_size])
    assign(socket, actions: actions, action_count: count, total_pages: total_pages, page: page)
  end

  defp table_patch(query, changes), do: "?" <> URI.encode_query(Map.merge(query, changes))

  defp column_patch(assigns, column) do
    order = if assigns.sort_by == column and assigns.sort_order == "asc", do: "desc", else: "asc"
    table_patch(assigns.query, %{"sort_by" => column, "sort_order" => order, "page" => "1"})
  end

  defp define_filters do
    results = ~w(succeeded failed skipped cancelled timed_out infrastructure_error unknown)

    [
      %Filter.Filter{
        id: "result",
        field: :result,
        display_name: dgettext("dashboard_projects", "Status"),
        type: :option,
        options: results,
        options_display_names: Map.new(results, &{&1, action_status_label(&1)}),
        operator: :==
      },
      %Filter.Filter{
        id: "cache",
        field: :cache,
        display_name: dgettext("dashboard_projects", "Cache"),
        type: :option,
        options: ["hit", "miss"],
        options_display_names: %{
          "hit" => dgettext("dashboard_projects", "Hit"),
          "miss" => dgettext("dashboard_projects", "Miss")
        },
        operator: :==
      }
    ]
  end

  defp empty_title(%{search: search, active_filters: filters}) when search != "" or filters != [] do
    dgettext("dashboard_projects", "No actions match your search or filters")
  end

  defp empty_title(%{run: %{finalization: "finalized"}}), do: dgettext("dashboard_projects", "No actions recorded")
  defp empty_title(_), do: dgettext("dashboard_projects", "Waiting for actions…")

  defp redacted_command?(run), do: String.contains?(run.command_display || "", "⟨opaque⟩")

  defp command_display(run) do
    String.replace(run.command_display || run.run_id, "⟨opaque⟩", dgettext("dashboard_projects", "[redacted]"))
  end

  defp run_title(run) do
    if redacted_command?(run) do
      case run.kind do
        "build" -> dgettext("dashboard_projects", "Once build")
        "test" -> dgettext("dashboard_projects", "Once test")
        _ -> dgettext("dashboard_projects", "Once run")
      end
    else
      run.command_display || run.run_id
    end
  end

  defp git_rev_present?(%{git_rev: rev}) when is_binary(rev) and rev != "", do: true
  defp git_rev_present?(_), do: false
  defp host_class_present?(%{host_class: host}) when is_binary(host) and host != "", do: true
  defp host_class_present?(_), do: false
  defp once_version_present?(%{once_version: v}) when is_binary(v) and v != "", do: true
  defp once_version_present?(_), do: false

  defp git_short_sha(rev) when is_binary(rev), do: String.slice(rev, 0, 12)

  defp run_status_label(%{finalization: "finalized", exit_status: 0}), do: dgettext("dashboard_builds", "Passed")

  defp run_status_label(%{finalization: "finalized"}), do: dgettext("dashboard_builds", "Failed")

  defp run_status_label(_), do: dgettext("dashboard_projects", "Running")

  defp run_status_badge_color(%{finalization: "finalized", exit_status: 0}), do: "success"
  defp run_status_badge_color(%{finalization: "finalized"}), do: "destructive"
  defp run_status_badge_color(_), do: "primary"

  # (Above is for the fill Badge which accepts destructive/primary; the
  # status_badge_cell used in tables uses a different enum — see
  # once_runs_live.ex :status_variant.)

  defp action_status_variant(%{result: "succeeded"}), do: "success"
  defp action_status_variant(%{result: "failed"}), do: "error"
  defp action_status_variant(_), do: "in_progress"

  defp action_label(%{identifier: identifier}) when is_binary(identifier) and identifier != "", do: identifier

  defp action_label(%{action_index: index}) do
    dgettext("dashboard_projects", "Action %{index}", index: index + 1)
  end

  defp kind_label("build"), do: dgettext("dashboard_projects", "Build")
  defp kind_label("test"), do: dgettext("dashboard_projects", "Test")
  defp kind_label(_), do: dgettext("dashboard_projects", "Generic")

  defp action_status_label("succeeded"), do: dgettext("dashboard_projects", "Succeeded")
  defp action_status_label("failed"), do: dgettext("dashboard_projects", "Failed")
  defp action_status_label("skipped"), do: dgettext("dashboard_projects", "Skipped")
  defp action_status_label("cancelled"), do: dgettext("dashboard_projects", "Cancelled")
  defp action_status_label("timed_out"), do: dgettext("dashboard_projects", "Timed out")
  defp action_status_label("infrastructure_error"), do: dgettext("dashboard_projects", "Infrastructure error")
  defp action_status_label(_), do: dgettext("dashboard_projects", "Unknown")

  defp format_duration_ms(nil), do: dgettext("dashboard_projects", "Unknown")
  defp format_duration_ms(ms), do: DateFormatter.format_duration_from_milliseconds(ms)
end
