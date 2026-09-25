defmodule TuistWeb.OnceRunsLive do
  @moduledoc """
  Once builds/tests/runs listing. A one-to-one clone of
  `TuistWeb.BazelInvocationsLive` — same layout, same `data-part`s so
  the Bazel invocations CSS applies verbatim — with data sourced from
  `Tuist.OnceEvents.Analytics` instead of `Tuist.Bazel`.
  """
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.BazelAnalyticsHelpers
  import TuistWeb.Components.ChartTypeToggle
  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.ScatterChart
  import TuistWeb.Components.Skeleton
  import TuistWeb.PercentileDropdownWidget

  alias Noora.Filter
  alias Phoenix.LiveView.AsyncResult
  alias Tuist.OnceEvents
  alias Tuist.OnceEvents.Analytics
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Utilities.Query
  alias TuistWeb.Utilities.SHA

  @page_size 20

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    # `summary_card?` is what makes the Builds page's card the Xcode shaped
    # one: a chart over the latest few runs with a View more button, instead
    # of the filterable, paginated listing the dedicated Build
    # Runs and Test Runs pages are.
    {resource, table_title, resource_kind, kind_filter, base_path, show_analytics?, summary_card?} =
      case socket.assigns[:live_action] do
        :tests ->
          {dgettext("dashboard_projects", "Test Runs"), dgettext("dashboard_projects", "Test Runs"), :tests, "test",
           "once/test-runs", true, false}

        :build_runs ->
          {dgettext("dashboard_projects", "Build Runs"), dgettext("dashboard_projects", "Build Runs"), :builds, "build",
           "once/build-runs", false, false}

        _ ->
          # The Builds page is an overview whose table lists the latest runs,
          # so the card is titled the way the Xcode and Gradle builds pages
          # title theirs rather than repeating the page name.
          {dgettext("dashboard_projects", "Builds"), dgettext("dashboard_builds", "Recent Builds"), :builds, "build",
           "once/builds", true, true}
      end

    socket =
      socket
      |> assign(:once_resource, resource)
      |> assign(:once_table_title, table_title)
      |> assign(:once_resource_kind, resource_kind)
      |> assign(:once_base_path, base_path)
      |> assign(:once_kind_filter, kind_filter)
      |> assign(:once_show_analytics, show_analytics?)
      |> assign(:once_summary_card, summary_card?)
      |> assign(:head_title, "#{resource} · #{account.name}/#{project.name} · Tuist")
      |> assign(:available_filters, define_filters())

    if connected?(socket) do
      OnceEvents.subscribe_project(project.id)
    end

    {:ok, socket}
  end

  def handle_params(params, _uri, %{assigns: %{selected_project: project}} = socket) do
    page = parse_page(params["page"])
    sort_by = params["invocations-sort-by"] || "ran-at"
    sort_order = params["invocations-sort-order"] || "desc"
    uri = URI.new!("?" <> URI.encode_query(params))
    active_filters = Filter.Operations.decode_filters_from_query(params, socket.assigns.available_filters)

    %{preset: analytics_preset, period: analytics_period} =
      DatePicker.date_picker_params(params, "analytics")

    analytics_selected_widget = params["analytics-selected-widget"] || "build-duration"
    insights_dimension = insights_dimension(params["configuration-insights-type"])
    analytics_environment = analytics_environment(params["analytics-environment"])
    search = String.trim(params["search"] || "")

    filters =
      [%{field: :project_id, op: :==, value: project.id}] ++
        search_filters(search) ++
        Filter.Operations.convert_filters_to_flop(active_filters)

    commands = [socket.assigns.once_kind_filter]
    analytics_opts = analytics_opts(analytics_period, commands, analytics_environment)

    # The dedicated listing pages carry no date picker, the way Xcode's own
    # Build Runs page does not, so scoping their table to a period would put
    # older runs out of reach with no control to widen the window.
    listing_opts =
      if socket.assigns.once_show_analytics,
        do: analytics_opts,
        else: Keyword.drop(analytics_opts, [:start_datetime, :end_datetime])

    {invocations, meta} =
      Analytics.list_invocations(
        project.id,
        %{
          filters: filters,
          order_by: [sort_field(sort_by)],
          order_directions: [sort_direction(sort_order)],
          page: page,
          page_size: @page_size,
          commands: commands
        },
        listing_opts
      )

    has_any_invocations = Enum.any?(invocations) || Analytics.invocations_present?(project.id, commands)

    socket =
      socket
      |> assign(:uri, uri)
      |> assign(:invocations, invocations)
      |> assign(:current_page, meta.current_page)
      |> assign(:total_pages, meta.total_pages)
      |> assign(:invocations_sort_by, sort_by)
      |> assign(:invocations_sort_order, sort_order)
      |> assign(:analytics_preset, analytics_preset)
      |> assign(:analytics_period, analytics_period)
      |> assign(:analytics_granularity, time_series_granularity(analytics_period))
      |> assign(:analytics_trend_label, analytics_trend_label(analytics_preset))
      |> assign(:analytics_selected_widget, analytics_selected_widget)
      |> assign(:has_any_invocations, has_any_invocations)
      |> assign(:selected_duration_type, params["duration-type"] || "avg")
      |> assign(:active_filters, active_filters)
      |> assign(:duration_chart_type, duration_chart_type(params["build-duration-chart-type"]))
      |> assign(:duration_scatter_group_by, scatter_group_by(params["build-duration-scatter-group-by"]))
      |> assign_duration_scatter(
        duration_chart_type(params["build-duration-chart-type"]),
        scatter_group_by(params["build-duration-scatter-group-by"]),
        analytics_period,
        commands,
        analytics_environment
      )
      |> assign_async([:invocation_summary, :invocation_analytics], fn ->
        {:ok,
         %{
           invocation_summary:
             invocation_summary_with_trends(project.id, analytics_period, commands, analytics_environment),
           invocation_analytics: Analytics.invocation_analytics(project.id, analytics_opts)
         }}
      end)
      |> assign(:search, search)
      |> assign(:analytics_environment, analytics_environment)
      |> assign(:analytics_environment_label, analytics_environment_label(analytics_environment))
      |> assign(:configuration_insights_dimension, insights_dimension)
      |> assign_async(:configuration_insights_analytics, fn ->
        {:ok,
         %{
           configuration_insights_analytics:
             Analytics.build_duration_analytics_by(
               project.id,
               String.to_existing_atom(insights_dimension),
               analytics_opts
             )
         }}
      end)
      |> assign_async(:recent_runs_chart, fn ->
        {:ok, %{recent_runs_chart: recent_runs_chart(project.id, analytics_opts)}}
      end)

    {:noreply, socket}
  end

  def handle_info({:run_updated, _run_id}, socket) do
    handle_params(URI.decode_query(socket.assigns.uri.query || ""), nil, socket)
  end

  def handle_event("select_duration_type", %{"type" => type}, socket) do
    query =
      socket.assigns.uri.query
      |> Query.put("duration-type", type)
      |> Query.put("analytics-selected-widget", "build-duration")

    {:noreply,
     socket
     |> assign(:selected_duration_type, type)
     |> assign(:analytics_selected_widget, "build-duration")
     |> assign(:uri, URI.new!("?" <> query))
     |> push_event("replace-url", %{url: "?" <> query})}
  end

  def handle_event("select_duration_chart_type", %{"type" => type}, socket) do
    query = Query.put(socket.assigns.uri.query, "build-duration-chart-type", type)
    type = duration_chart_type(type)

    {:noreply,
     socket
     |> assign(:duration_chart_type, type)
     |> assign(:uri, URI.new!("?" <> query))
     |> push_event("replace-url", %{url: "?" <> query})
     |> assign_duration_scatter(
       type,
       socket.assigns.duration_scatter_group_by,
       socket.assigns.analytics_period,
       [socket.assigns.once_kind_filter],
       socket.assigns.analytics_environment
     )}
  end

  def handle_event("search", %{"search" => search}, socket) do
    query =
      socket.assigns.uri.query
      |> Query.put("search", search)
      |> Query.put("page", "1")

    {:noreply, push_patch(socket, to: invocation_list_path(socket, URI.decode_query(query)))}
  end

  def handle_event("select_widget", %{"widget" => widget}, socket) do
    query = Query.put(socket.assigns.uri.query, "analytics-selected-widget", widget)

    {:noreply,
     socket
     |> assign(:analytics_selected_widget, widget)
     |> assign(:uri, URI.new!("?" <> query))
     |> push_event("replace-url", %{url: "?" <> query})}
  end

  def handle_event(
        "analytics_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        socket
      ) do
    query_params =
      if preset == "custom" do
        socket.assigns.uri.query
        |> Query.put("analytics-date-range", "custom")
        |> Query.put("analytics-start-date", start_date)
        |> Query.put("analytics-end-date", end_date)
      else
        Query.put(socket.assigns.uri.query, "analytics-date-range", preset)
      end

    {:noreply, push_patch(socket, to: invocation_list_path(socket, URI.decode_query(query_params)))}
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params =
      filter_id
      |> Filter.Operations.add_filter_to_query(socket)
      |> Map.put("page", "1")

    socket
    |> push_patch(to: invocation_list_path(socket, updated_params))
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
    |> push_patch(to: invocation_list_path(socket, updated_params))
    |> push_event("close-dropdown", %{id: "all", all: true})
    |> push_event("close-popover", %{id: "all", all: true})
    |> then(&{:noreply, &1})
  end

  def render(assigns) do
    ~H"""
    <div id="bazel-invocations" class="bazel-invocations">
      <div :if={@once_show_analytics} data-part="filters">
        <.dropdown
          id="once-analytics-environment-dropdown"
          label={@analytics_environment_label}
          secondary_text={dgettext("dashboard_tests", "Environment:")}
        >
          <.dropdown_item
            :for={environment <- ~w(any local ci)}
            value={environment}
            label={analytics_environment_label(environment)}
            patch={"?#{Query.put(@uri.query, "analytics-environment", environment)}"}
            data-selected={@analytics_environment == environment}
          >
            <:right_icon :if={@analytics_environment == environment}><.check /></:right_icon>
          </.dropdown_item>
        </.dropdown>
        <.date_picker
          id="once-invocations-date-range-picker"
          name="analytics-date-range"
          presets={date_picker_presets()}
          selected_preset={@analytics_preset}
          period={@analytics_period}
          on_period_change="analytics_period_changed"
          max={Date.utc_today()}
        >
          <:actions>
            <.button
              label={dgettext("dashboard_projects", "Cancel")}
              variant="secondary"
              phx-click={
                JS.dispatch("phx:date-picker-cancel",
                  detail: %{id: "once-invocations-date-range-picker"}
                )
              }
            />
            <.button
              label={dgettext("dashboard_projects", "Apply")}
              phx-click={
                JS.dispatch("phx:date-picker-apply",
                  detail: %{id: "once-invocations-date-range-picker"}
                )
              }
            />
          </:actions>
        </.date_picker>
      </div>
      <.card
        :if={@once_show_analytics}
        title={dgettext("dashboard_projects", "Analytics")}
        icon="chart_arcs"
        data-part="bazel-invocation-analytics-card"
      >
        <div data-part="widgets">
          <.widget
            id="once-total-invocations"
            loading={!@invocation_summary.ok?}
            title={
              if @once_resource_kind == :tests,
                do: dgettext("dashboard_tests", "Test run count"),
                else: dgettext("dashboard_projects", "Total builds")
            }
            legend_color="primary"
            description={
              if @once_resource_kind == :tests,
                do: dgettext("dashboard_tests", "The total number of test runs."),
                else:
                  dgettext("dashboard_projects", "Completed once commands in the selected period.")
            }
            value={if @invocation_summary.ok?, do: @invocation_summary.result.total}
            trend_value={if @invocation_summary.ok?, do: @invocation_summary.result.total_trend}
            trend_label={@analytics_trend_label}
            empty={@invocation_summary.ok? && @invocation_summary.result.total == 0}
            phx_click="select_widget"
            phx_value_widget="total-builds"
            selected={@analytics_selected_widget == "total-builds"}
          />
          <.widget
            :if={@once_resource_kind != :tests}
            id="once-success-rate"
            loading={!@invocation_summary.ok?}
            title={dgettext("dashboard_projects", "Build success rate")}
            legend_color="primary"
            description={
              dgettext(
                "dashboard_projects",
                "The share of completed commands with a zero exit code."
              )
            }
            value={if @invocation_summary.ok?, do: success_rate(@invocation_summary.result)}
            trend_value={
              if @invocation_summary.ok?, do: @invocation_summary.result.success_rate_trend
            }
            trend_label={@analytics_trend_label}
            empty={@invocation_summary.ok? && @invocation_summary.result.total == 0}
            phx_click="select_widget"
            phx_value_widget="build-success-rate"
            selected={@analytics_selected_widget == "build-success-rate"}
          />
          <.widget
            id="once-failed-invocations"
            loading={!@invocation_summary.ok?}
            title={
              if @once_resource_kind == :tests,
                do: dgettext("dashboard_tests", "Failed run count"),
                else: dgettext("dashboard_projects", "Failed builds")
            }
            legend_color="destructive"
            description={
              if @once_resource_kind == :tests,
                do: dgettext("dashboard_tests", "The number of test runs that failed."),
                else: dgettext("dashboard_projects", "Completed commands with a nonzero exit code.")
            }
            value={if @invocation_summary.ok?, do: @invocation_summary.result.failed}
            trend_value={if @invocation_summary.ok?, do: @invocation_summary.result.failed_trend}
            trend_label={@analytics_trend_label}
            trend_type={:inverse}
            empty={@invocation_summary.ok? && @invocation_summary.result.total == 0}
            phx_click="select_widget"
            phx_value_widget="failed-builds"
            selected={@analytics_selected_widget == "failed-builds"}
          />
          <.widget
            :if={@once_resource_kind == :tests}
            id="once-line-coverage"
            loading={false}
            title={dgettext("dashboard_tests", "Line coverage")}
            legend_color="primary"
            description={dgettext("dashboard_tests", "Test coverage isn't reported yet.")}
            value={nil}
            trend_value={0}
            trend_label={@analytics_trend_label}
            empty={true}
          />
          <.percentile_dropdown_widget
            id="once-invocation-duration"
            loading={!@invocation_summary.ok?}
            title={duration_title(@once_resource_kind, @selected_duration_type)}
            description={
              if @once_resource_kind == :tests,
                do:
                  dgettext(
                    "dashboard_tests",
                    "The average test run duration with individual percentile intervals."
                  ),
                else:
                  dgettext(
                    "dashboard_projects",
                    "The duration of completed once commands, with average and percentile views."
                  )
            }
            value={
              if @invocation_summary.ok?,
                do:
                  DateFormatter.format_duration_from_milliseconds(
                    duration_value(@invocation_summary.result, @selected_duration_type)
                  )
            }
            metrics={if @invocation_summary.ok?, do: duration_metrics(@invocation_summary.result)}
            selected_type={@selected_duration_type}
            legend_color={duration_legend_color(@selected_duration_type)}
            event_name="select_duration_type"
            phx_click="select_widget"
            phx_value_widget="build-duration"
            selected={@analytics_selected_widget == "build-duration"}
            trend_value={
              if @invocation_summary.ok?,
                do: duration_trend(@invocation_summary.result, @selected_duration_type)
            }
            trend_label={@analytics_trend_label}
            trend_type={:inverse}
            empty={@invocation_summary.ok? && @invocation_summary.result.total == 0}
          />
        </div>
        <.card_section :if={!@invocation_analytics.ok?} data-part="analytics-card-chart-section">
          <.skeleton_chart />
        </.card_section>
        <.card_section
          :if={
            @invocation_analytics.ok? &&
              analytics_has_data?(@invocation_analytics.result)
          }
          data-part="analytics-card-chart-section"
        >
          <.chart_type_toggle
            :if={@analytics_selected_widget == "build-duration"}
            id="once-build-duration"
            chart_type={@duration_chart_type}
            chart_type_event="select_duration_chart_type"
            group_by_options={[
              %{value: "host", label: dgettext("dashboard_projects", "Host")},
              %{value: "version", label: dgettext("dashboard_projects", "Once version")}
            ]}
            selected_group_by={@duration_scatter_group_by}
            group_by_query_param="build-duration-scatter-group-by"
            uri={@uri}
          />
          <.scatter_chart
            :if={@analytics_selected_widget == "build-duration" and @duration_chart_type == "scatter"}
            id="once-build-duration-scatter-chart"
            chart={@duration_chart}
            period={@analytics_period}
            value_format="fn:formatMilliseconds"
            url_fn={
              fn point ->
                ~p"/#{@selected_account.name}/#{@selected_project.name}/once/runs/#{point.id}"
              end
            }
            truncation_title={
              dgettext(
                "dashboard_projects",
                "The 1,000 run limit has been reached, data is only included up to %{date}. Try narrowing the date range to see more recent runs.",
                date: scatter_oldest_entry_formatted(@duration_chart.result)
              )
            }
          />
          <.chart
            :if={
              not (@analytics_selected_widget == "build-duration" and
                     @duration_chart_type == "scatter")
            }
            id="once-builds-analytics-chart"
            type="line"
            extra_options={
              analytics_chart_options(
                @invocation_analytics.result.dates,
                @analytics_selected_widget,
                @analytics_granularity
              )
            }
            series={analytics_chart_series(@invocation_analytics.result, @analytics_selected_widget)}
            y_axis_min={0}
            y_axis_max={if @analytics_selected_widget == "build-success-rate", do: 100}
          />
        </.card_section>
        <.empty_card_section
          :if={
            @invocation_analytics.ok? &&
              !analytics_has_data?(@invocation_analytics.result)
          }
          title={dgettext("dashboard_projects", "No once runs in this period")}
          data-part="analytics-card-chart-section"
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
      </.card>

      <.card
        :if={@once_show_analytics && @once_resource_kind != :tests}
        title={dgettext("dashboard_builds", "Configuration Insights")}
        icon="device_laptop"
        data-part="configuration-insights-card"
      >
        <:actions>
          <.dropdown
            id="once-configuration-insights-type-dropdown"
            label={insights_dimension_label(@configuration_insights_dimension)}
            secondary_text={dgettext("dashboard_builds", "Type:")}
          >
            <.dropdown_item
              :for={dimension <- ~w(version host environment)}
              value={dimension}
              label={insights_dimension_label(dimension)}
              patch={"?#{Query.put(@uri.query, "configuration-insights-type", dimension)}"}
              data-selected={@configuration_insights_dimension == dimension}
            >
              <:right_icon><.check /></:right_icon>
            </.dropdown_item>
          </.dropdown>
        </:actions>
        <.card_section :if={!@configuration_insights_analytics.ok?}>
          <div data-part="configuration-insights-chart-skeleton">
            <.skeleton_legend />
            <.skeleton_chart />
          </div>
        </.card_section>
        <.card_section
          :if={
            @configuration_insights_analytics.ok? &&
              not Enum.empty?(@configuration_insights_analytics.result)
          }
          data-part="configuration-insights-card-chart-section"
        >
          <.legend title={dgettext("dashboard_builds", "Build duration")} style="secondary" />
          <.chart
            id="once-configuration-insights-chart"
            type="line"
            style={"height: #{configuration_insights_chart_height(@configuration_insights_analytics.result)}px"}
            extra_options={
              configuration_insights_chart_options(@configuration_insights_analytics.result)
            }
            series={[
              %{
                color: "var:noora-chart-secondary",
                data: Enum.map(@configuration_insights_analytics.result, & &1.value),
                name: dgettext("dashboard_builds", "Build duration"),
                type: "bar",
                smooth: 0.1,
                symbol: "none"
              }
            ]}
            bar_width={8}
            bar_radius={2}
            x_axis_min={0}
          />
        </.card_section>
        <.empty_card_section
          :if={
            @configuration_insights_analytics.ok? &&
              Enum.empty?(@configuration_insights_analytics.result)
          }
          title={dgettext("dashboard_builds", "No data yet")}
        >
          <:image>
            <img
              src={~p"/images/empty_horizontal_bar_chart_light.png"}
              data-theme="light"
              loading="lazy"
              decoding="async"
            />
            <img
              src={~p"/images/empty_horizontal_bar_chart_dark.png"}
              data-theme="dark"
              loading="lazy"
              decoding="async"
            />
          </:image>
        </.empty_card_section>
      </.card>

      <.card
        title={@once_table_title}
        icon="subtask"
        data-part="bazel-invocations-card"
      >
        <:actions :if={@once_summary_card}>
          <.button
            variant="secondary"
            label={dgettext("dashboard_builds", "View more")}
            size="medium"
            navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/once/build-runs"}
            disabled={Enum.empty?(@invocations)}
          />
        </:actions>
        <.card_section
          :if={@once_summary_card && !@recent_runs_chart.ok?}
          data-part="recent-builds-card-section"
        >
          <div data-part="builds-chart">
            <div data-part="legends"><.skeleton_legend /><.skeleton_legend /></div>
            <.skeleton_chart />
          </div>
        </.card_section>
        <.card_section
          :if={
            @once_summary_card && @recent_runs_chart.ok? &&
              Enum.any?(@recent_runs_chart.result.points)
          }
          data-part="recent-builds-card-section"
        >
          <div data-part="builds-chart">
            <div data-part="legends">
              <.legend
                title={successful_runs_legend(@once_resource_kind)}
                value={@recent_runs_chart.result.successful}
                style="primary"
              />
              <.legend
                title={failed_runs_legend(@once_resource_kind)}
                value={@recent_runs_chart.result.failed}
                style="destructive"
              />
            </div>
            <.chart
              id="once-recent-runs-chart"
              type="bar"
              extra_options={
                %{
                  grid: %{width: "98%", left: "0.4%", right: "7%", height: "88%", top: "5%"},
                  tooltip: %{valueFormat: "fn:formatMilliseconds", dateFormat: "minute"},
                  xAxis: %{
                    axisLabel: %{show: false},
                    data: Enum.map(@recent_runs_chart.result.points, & &1.date)
                  },
                  yAxis: %{
                    splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}},
                    axisLabel: %{
                      color: "var:noora-surface-label-secondary",
                      formatter: "fn:formatMilliseconds"
                    }
                  },
                  legend: %{show: false}
                }
              }
              series={[
                %{data: @recent_runs_chart.result.points, name: @once_resource, type: "bar"}
              ]}
              y_axis_min={0}
              grid_lines
              bar_width={8}
              bar_radius={2}
            />
          </div>
        </.card_section>
        <.card_section data-part="bazel-invocations-table-section">
          <div :if={!@once_summary_card} data-part="filters">
            <%!-- Xcode's Test Runs page leads with a search box and its Build
            Runs page with a Sort by dropdown, so each Once page follows its
            own counterpart rather than picking one for both. --%>
            <.form
              :if={@once_resource_kind == :tests}
              for={%{}}
              id="once-invocations-search-form"
              phx-change="search"
              phx-submit="search"
              phx-debounce="200"
            >
              <.text_input
                type="search"
                id="once-invocations-search"
                name="search"
                placeholder={dgettext("dashboard_tests", "Search...")}
                show_suffix={false}
                data-part="search"
                value={@search}
              />
            </.form>
            <.dropdown
              :if={@once_resource_kind != :tests}
              id="once-invocations-sort-by"
              label={invocations_sort_label(@invocations_sort_by)}
              secondary_text={dgettext("dashboard_builds", "Sort by:")}
            >
              <.dropdown_item
                :for={column <- ~w(duration ran-at)}
                value={column}
                label={invocations_sort_label(column)}
                patch={column_patch_sort(assigns, column)}
                data-selected={@invocations_sort_by == column}
              >
                <:right_icon><.check /></:right_icon>
              </.dropdown_item>
            </.dropdown>
            <.filter_dropdown
              id="once-invocations-filter-dropdown"
              label={dgettext("dashboard_projects", "Filter")}
              available_filters={@available_filters}
              active_filters={@active_filters}
            />
          </div>
          <div :if={!@once_summary_card && Enum.any?(@active_filters)} data-part="active-filters">
            <.active_filter :for={filter <- @active_filters} filter={filter} />
          </div>
          <div :if={Enum.any?(@invocations)} data-part="bazel-invocations-table">
            <.table
              id="once-invocations-table"
              rows={visible_invocations(@invocations, @once_summary_card)}
              row_key={fn run -> run.invocation_id end}
              row_navigate={
                fn invocation ->
                  invocation_detail_path(assigns, invocation.invocation_id)
                end
              }
            >
              <:col
                :let={invocation}
                label={dgettext("dashboard_projects", "Run")}
              >
                <.text_cell label={invocation.command} />
              </:col>
              <:col
                :let={invocation}
                label={dgettext("dashboard_projects", "Status")}
                patch={column_patch_sort(assigns, "status")}
                sort_order={@invocations_sort_by == "status" && @invocations_sort_order}
              >
                <.status_badge_cell
                  :if={invocation.status == "success"}
                  label={dgettext("dashboard_builds", "Passed")}
                  status="success"
                />
                <.status_badge_cell
                  :if={invocation.status == "failure"}
                  label={dgettext("dashboard_projects", "Failed")}
                  status="error"
                />
                <.status_badge_cell
                  :if={invocation.status not in ["success", "failure"]}
                  label={dgettext("dashboard_projects", "Running")}
                  status="in_progress"
                />
              </:col>
              <:col :let={invocation} label={dgettext("dashboard_builds", "Branch")}>
                <.text_cell
                  icon="git_branch"
                  label={
                    if(invocation.git_branch in [nil, ""], do: "None", else: invocation.git_branch)
                  }
                />
              </:col>
              <:col :let={invocation} label={dgettext("dashboard_builds", "Commit SHA")}>
                <.text_cell label={SHA.format_commit_sha(invocation.git_rev)} />
              </:col>
              <:col :let={invocation} label={dgettext("dashboard_builds", "Ran by")}>
                <.badge_cell
                  :if={invocation.is_ci}
                  label={dgettext("dashboard", "CI")}
                  icon="settings"
                  color="information"
                  style="light-fill"
                />
                <.badge_cell
                  :if={!invocation.is_ci}
                  label={dgettext("dashboard_projects", "Local")}
                  icon="user"
                  color="primary"
                  style="light-fill"
                />
              </:col>
              <:col
                :let={invocation}
                label={dgettext("dashboard_projects", "Duration")}
                patch={column_patch_sort(assigns, "duration")}
                sort_order={@invocations_sort_by == "duration" && @invocations_sort_order}
              >
                <.text_cell
                  label={DateFormatter.format_duration_from_milliseconds(invocation.duration_ms)}
                  icon="history"
                />
              </:col>
              <:col
                :let={invocation}
                label={dgettext("dashboard_projects", "Ran at")}
                patch={column_patch_sort(assigns, "ran-at")}
                sort_order={@invocations_sort_by == "ran-at" && @invocations_sort_order}
              >
                <.text_cell sublabel={DateFormatter.from_now(invocation.finished_at)} />
              </:col>
              <:col :let={invocation} label={dgettext("dashboard_projects", "Host")}>
                <.text_cell label={
                  if(invocation.host_class in [nil, ""],
                    do: dgettext("dashboard_builds", "Unknown"),
                    else: invocation.host_class
                  )
                } />
              </:col>
            </.table>
            <.pagination_group
              :if={!@once_summary_card && @total_pages > 1}
              current_page={@current_page}
              number_of_pages={@total_pages}
              page_patch={fn page -> "?#{Query.put(@uri.query, "page", to_string(page))}" end}
            />
          </div>
          <.empty_card_section
            :if={Enum.empty?(@invocations)}
            title={invocations_empty_state_title(@active_filters, @has_any_invocations)}
            data-part="empty-bazel-invocations-card-section"
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
        </.card_section>
      </.card>
    </div>
    """
  end

  # ---- Helpers ----------------------------------------------------------

  defp success_rate(summary) do
    if numeric(summary.total) == 0, do: nil, else: "#{Float.round(success_rate_value(summary), 1)}%"
  end

  defp invocations_sort_label("duration"), do: dgettext("dashboard_builds", "Duration")
  defp invocations_sort_label(_ran_at), do: dgettext("dashboard_builds", "Ran at")

  # An unknown or absent query value falls back to the Once release rather
  # than reaching `String.to_existing_atom/1` with arbitrary input.
  defp insights_dimension(type) when type in ~w(version host environment), do: type
  defp insights_dimension(_unknown), do: "version"

  defp insights_dimension_label("host"), do: dgettext("dashboard_projects", "Host")
  defp insights_dimension_label("environment"), do: dgettext("dashboard_projects", "Environment")
  defp insights_dimension_label(_version), do: dgettext("dashboard_projects", "Once version")

  # The summary card shows only the latest handful, the way the Xcode Recent
  # Builds card takes 7 and sends the rest to its own listing page.
  @summary_card_rows 7

  defp visible_invocations(invocations, true), do: Enum.take(invocations, @summary_card_rows)
  defp visible_invocations(invocations, _paginated), do: invocations

  defp successful_runs_legend(:tests), do: dgettext("dashboard_projects", "Passed runs")
  defp successful_runs_legend(_builds), do: dgettext("dashboard_builds", "Successful builds")

  defp failed_runs_legend(:tests), do: dgettext("dashboard_projects", "Failed runs")
  defp failed_runs_legend(_builds), do: dgettext("dashboard_builds", "Failed builds")

  # The bar-per-run chart the Xcode Recent Builds card draws above its table:
  # newest last so the bars read left to right, coloured by status, with the
  # legend counts taken from the same window the bars cover.
  @recent_runs_chart_limit 30

  defp recent_runs_chart(project_id, analytics_opts) do
    {runs, _meta} =
      Analytics.list_invocations(
        project_id,
        %{
          page: 1,
          page_size: @recent_runs_chart_limit,
          order_by: [:finished_at],
          order_directions: [:desc]
        },
        analytics_opts
      )

    points =
      runs
      # A run still in flight has no verdict and no duration, so charting it
      # would draw a zero-height failure bar. The Xcode card excludes its
      # equivalent (`processing`) states for the same reason.
      |> Enum.filter(&(&1.status in ["success", "failure"]))
      |> Enum.reverse()
      |> Enum.map(fn run ->
        %{
          value: run.duration_ms || 0,
          itemStyle: %{
            color:
              if(run.status == "success",
                do: "var:noora-chart-primary",
                else: "var:noora-chart-destructive"
              )
          },
          date: run.finished_at,
          status: run.status
        }
      end)

    %{
      points: points,
      successful: Enum.count(points, &(&1.status == "success")),
      failed: Enum.count(points, &(&1.status == "failure"))
    }
  end

  defp invocation_summary_with_trends(project_id, {start_datetime, end_datetime} = period, commands, environment) do
    summary = Analytics.summary(project_id, analytics_opts(period, commands, environment))

    previous_summary =
      Analytics.summary(
        project_id,
        analytics_opts(previous_period(start_datetime, end_datetime), commands, environment)
      )

    Map.merge(summary, %{
      total_trend: trend(previous_summary.total, summary.total),
      success_rate_trend: trend(success_rate_value(previous_summary), success_rate_value(summary)),
      failed_trend: trend(previous_summary.failed, summary.failed),
      average_duration_trend: trend(previous_summary.average_duration_ms, summary.average_duration_ms),
      median_duration_trend: trend(previous_summary.median_duration_ms, summary.median_duration_ms),
      p90_duration_trend: trend(previous_summary.p90_duration_ms, summary.p90_duration_ms),
      p99_duration_trend: trend(previous_summary.p99_duration_ms, summary.p99_duration_ms)
    })
  end

  defp success_rate_value(summary) do
    total = numeric(summary.total)
    if total == 0, do: 0.0, else: numeric(summary.successful) / total * 100
  end

  defp duration_title(:tests, "p99"), do: dgettext("dashboard_tests", "p99 test run duration")
  defp duration_title(:tests, "p90"), do: dgettext("dashboard_tests", "p90 test run duration")
  defp duration_title(:tests, "p50"), do: dgettext("dashboard_tests", "p50 test run duration")
  defp duration_title(:tests, _), do: dgettext("dashboard_tests", "Avg. test run duration")
  defp duration_title(_, "p99"), do: dgettext("dashboard_projects", "p99 build duration")
  defp duration_title(_, "p90"), do: dgettext("dashboard_projects", "p90 build duration")
  defp duration_title(_, "p50"), do: dgettext("dashboard_projects", "p50 build duration")
  defp duration_title(_, _), do: dgettext("dashboard_projects", "Avg. build duration")

  defp invocations_empty_state_title([_ | _], _has_any),
    do: dgettext("dashboard_projects", "No once builds match the current filters.")

  defp invocations_empty_state_title([], true),
    do: dgettext("dashboard_projects", "No once builds in the selected period.")

  defp invocations_empty_state_title([], false),
    do: dgettext("dashboard_projects", "No once builds have been received yet.")

  defp duration_value(summary, "p99"), do: numeric(summary.p99_duration_ms)
  defp duration_value(summary, "p90"), do: numeric(summary.p90_duration_ms)
  defp duration_value(summary, "p50"), do: numeric(summary.median_duration_ms)
  defp duration_value(summary, _), do: numeric(summary.average_duration_ms)

  defp duration_metrics(summary) do
    %{
      avg: DateFormatter.format_duration_from_milliseconds(summary.average_duration_ms),
      p99: DateFormatter.format_duration_from_milliseconds(summary.p99_duration_ms),
      p90: DateFormatter.format_duration_from_milliseconds(summary.p90_duration_ms),
      p50: DateFormatter.format_duration_from_milliseconds(summary.median_duration_ms)
    }
  end

  defp duration_trend(summary, "p99"), do: summary.p99_duration_trend
  defp duration_trend(summary, "p90"), do: summary.p90_duration_trend
  defp duration_trend(summary, "p50"), do: summary.median_duration_trend
  defp duration_trend(summary, _), do: summary.average_duration_trend

  defp duration_legend_color("p99"), do: "p99"
  defp duration_legend_color("p90"), do: "p90"
  defp duration_legend_color("p50"), do: "p50"
  defp duration_legend_color(_), do: "secondary"

  defp analytics_has_data?(analytics), do: Enum.any?(analytics.total_values, &(numeric(&1) > 0))

  defp analytics_chart_options(dates, "build-duration", granularity) do
    %{
      legend: chart_legend(),
      grid: %{width: "97%", left: "0.4%", height: "60%", top: "10%"},
      xAxis: chart_x_axis(dates, granularity),
      yAxis: chart_y_axis("fn:formatMilliseconds"),
      tooltip: chart_tooltip("fn:formatMilliseconds", granularity)
    }
  end

  defp analytics_chart_options(dates, "build-success-rate", granularity) do
    %{
      grid: %{width: "97%", left: "0.4%", height: "88%", top: "5%"},
      xAxis: chart_x_axis(dates, granularity),
      yAxis: chart_y_axis("{value}%"),
      legend: %{show: false},
      tooltip: chart_tooltip("{value}%", granularity)
    }
  end

  defp analytics_chart_options(dates, _widget, granularity) do
    %{
      grid: %{width: "97%", left: "0.4%", height: "88%", top: "5%"},
      xAxis: chart_x_axis(dates, granularity),
      yAxis: chart_y_axis("{value}"),
      legend: %{show: false},
      tooltip: chart_tooltip("{value}", granularity)
    }
  end

  defp analytics_chart_series(analytics, "total-builds") do
    [
      chart_series(
        analytics.dates,
        analytics.total_values,
        "var:noora-chart-primary",
        dgettext("dashboard_projects", "Completed commands")
      )
    ]
  end

  defp analytics_chart_series(analytics, "build-success-rate") do
    [
      chart_series(
        analytics.dates,
        analytics.success_rate_values,
        "var:noora-chart-primary",
        dgettext("dashboard_projects", "Build success rate")
      )
    ]
  end

  defp analytics_chart_series(analytics, "failed-builds") do
    [
      chart_series(
        analytics.dates,
        analytics.failed_values,
        "var:noora-chart-destructive",
        dgettext("dashboard_projects", "Failed builds")
      )
    ]
  end

  defp analytics_chart_series(analytics, _widget) do
    [
      chart_series(
        analytics.dates,
        analytics.average_duration_values,
        "var:noora-chart-secondary",
        dgettext("dashboard_projects", "Average")
      ),
      chart_series(analytics.dates, analytics.p99_duration_values, "var:noora-chart-p99", "p99"),
      chart_series(analytics.dates, analytics.p90_duration_values, "var:noora-chart-p90", "p90"),
      chart_series(analytics.dates, analytics.median_duration_values, "var:noora-chart-p50", "p50")
    ]
  end

  defp configuration_insights_chart_height(analytics), do: max(Enum.count(analytics) * 28, 28)

  defp configuration_insights_chart_options(analytics) do
    %{
      grid: %{width: "98%", left: "50", height: "100%", top: "0%"},
      xAxis: %{
        boundaryGap: false,
        type: "value",
        axisLabel: %{
          color: "var:noora-surface-label-secondary",
          formatter: "fn:formatMilliseconds"
        }
      },
      yAxis: %{
        offset: 40,
        splitNumber: 4,
        type: "category",
        splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}},
        axisLabel: %{color: "var:noora-surface-label-secondary"},
        data: Enum.map(analytics, & &1.category)
      },
      legend: %{show: false},
      tooltip: %{valueFormat: "fn:formatMilliseconds"}
    }
  end

  defp chart_series(dates, values, color, name) do
    %{
      color: color,
      data: dates |> Enum.zip(values) |> Enum.map(&Tuple.to_list/1),
      name: name,
      type: "line",
      smooth: 0.1,
      symbol: "none"
    }
  end

  defp chart_legend do
    %{
      left: "left",
      top: "bottom",
      orient: "horizontal",
      textStyle: %{
        color: "var:noora-surface-label-secondary",
        fontFamily: "monospace",
        fontWeight: 400,
        fontSize: 10,
        lineHeight: 12
      },
      icon:
        "path://M0 6C0 4.89543 0.895431 4 2 4H6C7.10457 4 8 4.89543 8 6C8 7.10457 7.10457 8 6 8H2C0.895431 8 0 7.10457 0 6Z",
      itemWidth: 8,
      itemHeight: 4
    }
  end

  def column_patch_sort(
        %{uri: uri, invocations_sort_by: invocations_sort_by, invocations_sort_order: invocations_sort_order},
        column_value
      ) do
    sort_order =
      case {invocations_sort_by == column_value, invocations_sort_order} do
        {true, "asc"} -> "desc"
        {true, _} -> "asc"
        {false, _} -> "desc"
      end

    query_params =
      uri.query
      |> URI.decode_query()
      |> Map.put("invocations-sort-by", column_value)
      |> Map.put("invocations-sort-order", sort_order)
      |> Map.put("page", "1")

    "?#{URI.encode_query(query_params)}"
  end

  defp invocation_list_path(socket, params) do
    "/#{socket.assigns.selected_account.name}/#{socket.assigns.selected_project.name}/#{socket.assigns.once_base_path}?#{URI.encode_query(params)}"
  end

  defp invocation_detail_path(%{once_resource_kind: :tests} = assigns, invocation_id) do
    ~p"/#{assigns.selected_account.name}/#{assigns.selected_project.name}/once/test-runs/#{invocation_id}"
  end

  defp invocation_detail_path(assigns, invocation_id) do
    ~p"/#{assigns.selected_account.name}/#{assigns.selected_project.name}/once/runs/#{invocation_id}"
  end

  defp sort_field("command"), do: :command
  defp sort_field("status"), do: :status
  defp sort_field("duration"), do: :duration_ms
  defp sort_field(_), do: :finished_at

  defp analytics_opts(period, commands, environment) do
    period
    |> period_opts()
    |> Keyword.put(:commands, commands)
    |> put_environment(environment)
  end

  # `:is_ci` is the opt `Tuist.OnceEvents.Analytics` filters on, and the same
  # one `Tuist.Builds` takes for Xcode, so the dropdown means the same thing
  # on both build systems. "Any" leaves it unset rather than passing a value.
  defp put_environment(opts, "ci"), do: Keyword.put(opts, :is_ci, true)
  defp put_environment(opts, "local"), do: Keyword.put(opts, :is_ci, false)
  defp put_environment(opts, _any), do: opts

  # The runs list is searched by its displayed command, which is the only
  # free-text field a Once run carries.
  defp search_filters(""), do: []
  defp search_filters(search), do: [%{field: :command, op: :=~, value: search}]

  defp analytics_environment(environment) when environment in ~w(any local ci), do: environment
  defp analytics_environment(_unknown), do: "any"

  defp analytics_environment_label("local"), do: dgettext("dashboard_tests", "Local")
  defp analytics_environment_label("ci"), do: dgettext("dashboard_tests", "CI")
  defp analytics_environment_label(_any), do: dgettext("dashboard_tests", "Any")

  defp define_filters do
    [
      %Filter.Filter{
        id: "status",
        field: :status,
        display_name: dgettext("dashboard_projects", "Status"),
        type: :option,
        options: ["success", "failure"],
        options_display_names: %{
          "success" => dgettext("dashboard_builds", "Passed"),
          "failure" => dgettext("dashboard_projects", "Failed")
        },
        operator: :==,
        value: nil
      }
    ]
  end

  # Only the duration widget has a per-run value worth plotting; the other
  # widgets are counts and rates aggregated over the period.
  defp duration_chart_type("scatter"), do: "scatter"
  defp duration_chart_type(_line), do: "line"

  defp scatter_group_by("version"), do: "version"
  defp scatter_group_by(_host), do: "host"

  defp assign_duration_scatter(socket, "scatter", group_by, period, commands, environment) do
    project_id = socket.assigns.selected_project.id

    # Without the environment the scatter brings back runs the line chart
    # excludes, so toggling the chart type silently widens the selection.
    opts =
      period
      |> period_opts()
      |> Keyword.put(:commands, commands)
      |> Keyword.put(:group_by, String.to_existing_atom(group_by))
      |> put_environment(environment)

    assign_async(socket, :duration_chart, fn ->
      {:ok, %{duration_chart: {:scatter, Analytics.duration_scatter_data(project_id, opts)}}}
    end)
  end

  defp assign_duration_scatter(socket, _line, _group_by, _period, _commands, _environment) do
    assign(socket, :duration_chart, AsyncResult.ok(:line))
  end
end
