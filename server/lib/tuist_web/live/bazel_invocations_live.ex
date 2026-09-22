defmodule TuistWeb.BazelInvocationsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.BazelAnalyticsHelpers
  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.Skeleton
  import TuistWeb.PercentileDropdownWidget

  alias Noora.Filter
  alias Tuist.Bazel
  alias Tuist.Utilities.ByteFormatter
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  @page_size 20

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    resource = socket.assigns[:bazel_resource] || dgettext("dashboard_projects", "Invocations")
    resource_kind = socket.assigns[:bazel_resource_kind] || :invocations

    socket =
      socket
      |> assign(:bazel_resource, resource)
      |> assign(:bazel_resource_kind, resource_kind)
      |> assign(:bazel_base_path, socket.assigns[:bazel_base_path] || "invocations")
      |> assign(:bazel_invocation_commands, socket.assigns[:bazel_invocation_commands])
      |> assign(:bazel_show_analytics, socket.assigns[:bazel_show_analytics] != false)
      |> assign(:head_title, "#{resource} · #{account.name}/#{project.name} · Tuist")
      |> assign(OpenGraph.og_image_assigns("overview"))
      |> assign(:available_filters, define_filters(resource_kind))

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
    analytics_environment = analytics_environment_param(params["analytics-environment"])

    filters =
      [%{field: :project_id, op: :==, value: project.id}] ++
        build_flop_filters(active_filters)

    filters = maybe_add_environment_filter(filters, analytics_environment, socket.assigns.bazel_show_analytics)
    analytics_opts = analytics_opts(analytics_period, socket.assigns.bazel_invocation_commands, analytics_environment)

    list_opts =
      if socket.assigns.bazel_show_analytics do
        analytics_opts
      else
        [commands: socket.assigns.bazel_invocation_commands]
      end

    {invocations, meta} =
      Bazel.list_invocations(
        project.id,
        %{
          filters: filters,
          order_by: [sort_field(sort_by)],
          order_directions: [sort_direction(sort_order)],
          page: page,
          page_size: @page_size,
          commands: socket.assigns.bazel_invocation_commands
        },
        list_opts
      )

    commands = socket.assigns.bazel_invocation_commands
    has_any_invocations = Enum.any?(invocations) || Bazel.invocations_present?(project.id, commands)

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
      |> assign(:analytics_environment, analytics_environment)
      |> assign(:analytics_environment_label, environment_label(analytics_environment))
      |> assign(:analytics_selected_widget, analytics_selected_widget)
      |> assign(:has_any_invocations, has_any_invocations)
      |> assign(:selected_duration_type, params["duration-type"] || "avg")
      |> assign(:active_filters, active_filters)
      |> assign_async([:invocation_summary, :invocation_analytics], fn ->
        {:ok,
         %{
           invocation_summary:
             invocation_summary_with_trends(
               project.id,
               analytics_period,
               commands,
               analytics_environment
             ),
           invocation_analytics:
             Bazel.invocation_analytics(
               project.id,
               analytics_opts
             )
         }}
      end)

    socket =
      if socket.assigns.bazel_show_analytics and socket.assigns.bazel_resource_kind == :builds do
        assign_async(socket, :configuration_insights_analytics, fn ->
          {:ok,
           %{
             configuration_insights_analytics: Bazel.build_duration_analytics_by_version(project.id, analytics_opts)
           }}
        end)
      else
        socket
      end

    {:noreply, socket}
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
      <div :if={@bazel_show_analytics} data-part="filters">
        <.dropdown
          id="bazel-builds-environment-dropdown"
          label={@analytics_environment_label}
          secondary_text={dgettext("dashboard_projects", "Environment:")}
        >
          <.dropdown_item
            :for={{value, label} <- environment_options()}
            value={value}
            label={label}
            patch={"?#{Query.put(@uri.query, "analytics-environment", value)}"}
            data-selected={@analytics_environment == value}
          >
            <:right_icon :if={@analytics_environment == value}><.check /></:right_icon>
          </.dropdown_item>
        </.dropdown>
        <.date_picker
          id="bazel-invocations-date-range-picker"
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
                  detail: %{id: "bazel-invocations-date-range-picker"}
                )
              }
            />
            <.button
              label={dgettext("dashboard_projects", "Apply")}
              phx-click={
                JS.dispatch("phx:date-picker-apply",
                  detail: %{id: "bazel-invocations-date-range-picker"}
                )
              }
            />
          </:actions>
        </.date_picker>
      </div>
      <.card
        :if={@bazel_show_analytics}
        title={dgettext("dashboard_projects", "Analytics")}
        icon="chart_arcs"
        data-part="bazel-invocation-analytics-card"
      >
        <div data-part="widgets">
          <.widget
            id="bazel-total-invocations"
            loading={!@invocation_summary.ok?}
            title={metric_title(@bazel_resource_kind, :total)}
            legend_color="primary"
            description={
              dgettext("dashboard_projects", "Completed Bazel commands in the retained data window.")
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
            id="bazel-success-rate"
            loading={!@invocation_summary.ok?}
            title={metric_title(@bazel_resource_kind, :success_rate)}
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
            id="bazel-failed-invocations"
            loading={!@invocation_summary.ok?}
            title={metric_title(@bazel_resource_kind, :failed)}
            legend_color="destructive"
            description={
              dgettext("dashboard_projects", "Completed commands with a nonzero exit code.")
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
          <.percentile_dropdown_widget
            id="bazel-invocation-duration"
            loading={!@invocation_summary.ok?}
            title={duration_title(@selected_duration_type, @bazel_resource_kind)}
            description={
              dgettext(
                "dashboard_projects",
                "The duration of completed Bazel commands, with average and percentile views."
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
              analytics_has_data?(@invocation_analytics.result, @analytics_selected_widget)
          }
          data-part="analytics-card-chart-section"
        >
          <.chart
            id="bazel-builds-analytics-chart"
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
              !analytics_has_data?(@invocation_analytics.result, @analytics_selected_widget)
          }
          title={dgettext("dashboard_projects", "No Bazel invocations in this period")}
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
        :if={@bazel_show_analytics && @bazel_resource_kind == :builds}
        title={dgettext("dashboard_builds", "Configuration Insights")}
        icon="device_laptop"
        data-part="configuration-insights-card"
      >
        <:actions>
          <.dropdown
            id="bazel-configuration-insights-type-dropdown"
            label={dgettext("dashboard_projects", "Bazel version")}
            secondary_text={dgettext("dashboard_builds", "Type:")}
          >
            <.dropdown_item
              value="bazel-version"
              label={dgettext("dashboard_projects", "Bazel version")}
              patch={"?#{@uri.query}"}
              data-selected
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
            id="bazel-configuration-insights-chart"
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
        title={@bazel_resource}
        icon="subtask"
        data-part="bazel-invocations-card"
      >
        <.card_section data-part="bazel-invocations-table-section">
          <div data-part="filters">
            <.dropdown
              :if={!@bazel_show_analytics}
              id="bazel-invocations-sort-by"
              label={
                case @invocations_sort_by do
                  "duration" -> dgettext("dashboard_builds", "Duration")
                  _ -> dgettext("dashboard_builds", "Ran at")
                end
              }
              secondary_text={dgettext("dashboard_builds", "Sort by:")}
            >
              <.dropdown_item
                value="duration"
                label={dgettext("dashboard_builds", "Duration")}
                patch={column_patch_sort(assigns, "duration")}
                data-selected={@invocations_sort_by == "duration"}
              >
                <:right_icon :if={@invocations_sort_by == "duration"}><.check /></:right_icon>
              </.dropdown_item>
              <.dropdown_item
                value="ran-at"
                label={dgettext("dashboard_builds", "Ran at")}
                patch={column_patch_sort(assigns, "ran-at")}
                data-selected={@invocations_sort_by == "ran-at"}
              >
                <:right_icon :if={@invocations_sort_by == "ran-at"}><.check /></:right_icon>
              </.dropdown_item>
            </.dropdown>
            <.filter_dropdown
              id="bazel-invocations-filter-dropdown"
              label={dgettext("dashboard_projects", "Filter")}
              available_filters={@available_filters}
              active_filters={@active_filters}
            />
          </div>
          <div :if={Enum.any?(@active_filters)} data-part="active-filters">
            <.active_filter :for={filter <- @active_filters} filter={filter} />
          </div>
          <div :if={Enum.any?(@invocations)} data-part="bazel-invocations-table">
            <.table
              id="bazel-invocations-table"
              rows={@invocations}
              row_navigate={
                fn invocation ->
                  invocation_detail_path(assigns, invocation.invocation_id)
                end
              }
            >
              <:col
                :let={invocation}
                :if={@bazel_resource_kind == :builds}
                label={dgettext("dashboard_projects", "Invocation")}
              >
                <.text_cell label={requested_command(invocation)} />
              </:col>
              <:col
                :let={invocation}
                :if={@bazel_resource_kind != :builds}
                label={dgettext("dashboard_projects", "Targets")}
              >
                <.text_cell label={target_patterns_label(invocation.target_patterns)} />
              </:col>
              <:col
                :let={invocation}
                :if={@bazel_resource_kind != :builds}
                label={dgettext("dashboard_projects", "Command")}
                patch={column_patch_sort(assigns, "command")}
                sort_order={@invocations_sort_by == "command" && @invocations_sort_order}
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
                  label={
                    if invocation.status == "success",
                      do: dgettext("dashboard_projects", "Succeeded"),
                      else: dgettext("dashboard_projects", "Failed")
                  }
                  status={if invocation.status == "success", do: "success", else: "error"}
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
              <:col :let={invocation} label={dgettext("dashboard_projects", "Cache hit rate")}>
                <.text_cell label={cache_hit_rate(invocation.cache)} />
              </:col>
              <:col :let={invocation} label={dgettext("dashboard_projects", "Downloaded")}>
                <.text_cell label={ByteFormatter.format_bytes(invocation.cache.download_bytes)} />
              </:col>
              <:col :let={invocation} label={dgettext("dashboard_projects", "Uploaded")}>
                <.text_cell label={ByteFormatter.format_bytes(invocation.cache.upload_bytes)} />
              </:col>
              <:col
                :let={invocation}
                label={dgettext("dashboard_projects", "Ran at")}
                patch={column_patch_sort(assigns, "ran-at")}
                sort_order={@invocations_sort_by == "ran-at" && @invocations_sort_order}
              >
                <.text_cell sublabel={DateFormatter.from_now(invocation.finished_at)} />
              </:col>
            </.table>
            <.pagination_group
              :if={@total_pages > 1}
              current_page={@current_page}
              number_of_pages={@total_pages}
              page_patch={fn page -> "?#{Query.put(@uri.query, "page", to_string(page))}" end}
            />
          </div>
          <.empty_card_section
            :if={Enum.empty?(@invocations)}
            title={
              invocations_empty_state_title(
                @active_filters,
                @bazel_resource_kind,
                @has_any_invocations
              )
            }
            get_started_href={
              if Enum.empty?(@active_filters) && !@has_any_invocations,
                do: "https://tuist.dev/en/docs/guides/features/cache/bazel-cache"
            }
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

  defp success_rate(summary) do
    if numeric(summary.total) == 0, do: nil, else: "#{Float.round(success_rate_value(summary), 1)}%"
  end

  defp invocation_summary_with_trends(project_id, {start_datetime, end_datetime} = period, commands, environment) do
    summary = Bazel.summary(project_id, analytics_opts(period, commands, environment))

    previous_summary =
      Bazel.summary(project_id, analytics_opts(previous_period(start_datetime, end_datetime), commands, environment))

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

  defp metric_title(:builds, :total), do: dgettext("dashboard_projects", "Total builds")
  defp metric_title(:builds, :success_rate), do: dgettext("dashboard_projects", "Build success rate")
  defp metric_title(:builds, :failed), do: dgettext("dashboard_projects", "Failed builds")
  defp metric_title(_, :total), do: dgettext("dashboard_projects", "Total invocations")
  defp metric_title(_, :success_rate), do: dgettext("dashboard_projects", "Invocation success rate")
  defp metric_title(_, :failed), do: dgettext("dashboard_projects", "Failed invocations")

  defp duration_title("p99", :builds), do: dgettext("dashboard_projects", "p99 build duration")
  defp duration_title("p90", :builds), do: dgettext("dashboard_projects", "p90 build duration")
  defp duration_title("p50", :builds), do: dgettext("dashboard_projects", "p50 build duration")
  defp duration_title(_, :builds), do: dgettext("dashboard_projects", "Avg. build duration")
  defp duration_title("p99", _), do: dgettext("dashboard_projects", "p99 invocation duration")
  defp duration_title("p90", _), do: dgettext("dashboard_projects", "p90 invocation duration")
  defp duration_title("p50", _), do: dgettext("dashboard_projects", "p50 invocation duration")
  defp duration_title(_, _), do: dgettext("dashboard_projects", "Average invocation duration")

  defp empty_state_title(:builds), do: dgettext("dashboard_projects", "No Bazel builds have been received yet.")
  defp empty_state_title(_), do: dgettext("dashboard_projects", "No Bazel invocations have been received yet.")

  defp invocations_empty_state_title([_ | _], :builds, _has_any_invocations),
    do: dgettext("dashboard_projects", "No Bazel builds match the current filters.")

  defp invocations_empty_state_title([_ | _], _resource_kind, _has_any_invocations),
    do: dgettext("dashboard_projects", "No Bazel invocations match the current filters.")

  defp invocations_empty_state_title([], :builds, true),
    do: dgettext("dashboard_projects", "No Bazel builds in the selected period.")

  defp invocations_empty_state_title([], _resource_kind, true),
    do: dgettext("dashboard_projects", "No Bazel invocations in the selected period.")

  defp invocations_empty_state_title([], resource_kind, false), do: empty_state_title(resource_kind)

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

  defp analytics_has_data?(analytics, _widget), do: Enum.any?(analytics.total_values, &(numeric(&1) > 0))

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

  defp cache_hit_rate(%{hit_rate: nil}), do: dgettext("dashboard_projects", "No cache lookups")
  defp cache_hit_rate(%{hit_rate: hit_rate}), do: "#{hit_rate}%"

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
    "/#{socket.assigns.selected_account.name}/#{socket.assigns.selected_project.name}/#{socket.assigns.bazel_base_path}?#{URI.encode_query(params)}"
  end

  defp invocation_detail_path(%{bazel_resource_kind: :builds} = assigns, invocation_id) do
    ~p"/#{assigns.selected_account.name}/#{assigns.selected_project.name}/builds/invocations/#{invocation_id}"
  end

  defp invocation_detail_path(assigns, invocation_id) do
    ~p"/#{assigns.selected_account.name}/#{assigns.selected_project.name}/invocations/#{invocation_id}"
  end

  defp sort_field("command"), do: :command
  defp sort_field("status"), do: :status
  defp sort_field("duration"), do: :duration_ms
  defp sort_field(_), do: :finished_at

  defp analytics_environment_param(environment) when environment in ["ci", "local"], do: environment
  defp analytics_environment_param(_environment), do: "any"

  defp environment_label("ci"), do: dgettext("dashboard_projects", "CI")
  defp environment_label("local"), do: dgettext("dashboard_projects", "Local")
  defp environment_label(_environment), do: dgettext("dashboard_projects", "Any")

  defp environment_options do
    [
      {"any", dgettext("dashboard_projects", "Any")},
      {"ci", dgettext("dashboard_projects", "CI")},
      {"local", dgettext("dashboard_projects", "Local")}
    ]
  end

  defp analytics_opts(period, commands, environment) do
    period
    |> period_opts(commands)
    |> maybe_put_environment(environment)
  end

  defp maybe_put_environment(opts, "ci"), do: Keyword.put(opts, :is_ci, true)
  defp maybe_put_environment(opts, "local"), do: Keyword.put(opts, :is_ci, false)
  defp maybe_put_environment(opts, _environment), do: opts

  defp maybe_add_environment_filter(filters, "ci", true), do: [%{field: :is_ci, op: :==, value: true} | filters]

  defp maybe_add_environment_filter(filters, "local", true), do: [%{field: :is_ci, op: :==, value: false} | filters]

  defp maybe_add_environment_filter(filters, _environment, _show_analytics), do: filters

  defp build_flop_filters(filters) do
    {environment_filters, remaining_filters} = Enum.split_with(filters, &(&1.id == "is_ci"))

    environment_flop_filters =
      Enum.flat_map(environment_filters, fn
        %{value: :ci, operator: operator} -> [%{field: :is_ci, op: operator, value: true}]
        %{value: :local, operator: operator} -> [%{field: :is_ci, op: operator, value: false}]
        _ -> []
      end)

    Filter.Operations.convert_filters_to_flop(remaining_filters) ++ environment_flop_filters
  end

  defp define_filters(resource_kind) do
    status_filter =
      %Filter.Filter{
        id: "status",
        field: :status,
        display_name: dgettext("dashboard_projects", "Status"),
        type: :option,
        options: ["success", "failure"],
        options_display_names: %{
          "success" => dgettext("dashboard_projects", "Succeeded"),
          "failure" => dgettext("dashboard_projects", "Failed")
        },
        operator: :==,
        value: nil
      }

    command_filter =
      %Filter.Filter{
        id: "command",
        field: :command,
        display_name: dgettext("dashboard_projects", "Command"),
        type: :text,
        operator: :=~,
        value: ""
      }

    environment_filter =
      %Filter.Filter{
        id: "is_ci",
        field: :is_ci,
        display_name: dgettext("dashboard_projects", "Environment"),
        type: :option,
        options: [:ci, :local],
        options_display_names: %{
          ci: dgettext("dashboard_projects", "CI"),
          local: dgettext("dashboard_projects", "Local")
        },
        operator: :==,
        value: nil
      }

    if resource_kind == :builds,
      do: [status_filter, environment_filter],
      else: [status_filter, command_filter, environment_filter]
  end
end
