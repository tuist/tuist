defmodule TuistWeb.BazelInvocationsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

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

    socket =
      socket
      |> assign(:bazel_resource, resource)
      |> assign(:bazel_base_path, socket.assigns[:bazel_base_path] || "invocations")
      |> assign(:bazel_invocation_commands, socket.assigns[:bazel_invocation_commands])
      |> assign(:head_title, "#{resource} · #{account.name}/#{project.name} · Tuist")
      |> assign(OpenGraph.og_image_assigns("overview"))
      |> assign(:available_filters, define_filters())

    {:ok, socket}
  end

  def handle_params(params, _uri, %{assigns: %{selected_project: project}} = socket) do
    page = parse_page(params["page"])
    sort_by = params["invocations-sort-by"] || "finished-at"
    sort_order = params["invocations-sort-order"] || "desc"
    uri = URI.new!("?" <> URI.encode_query(params))
    active_filters = Filter.Operations.decode_filters_from_query(params, socket.assigns.available_filters)

    %{preset: analytics_preset, period: analytics_period} =
      DatePicker.date_picker_params(params, "analytics")

    analytics_selected_widget = params["analytics-selected-widget"] || "build-duration"

    filters =
      [%{field: :project_id, op: :==, value: project.id}] ++
        Filter.Operations.convert_filters_to_flop(active_filters)

    {invocations, meta} =
      Bazel.list_invocations(project.id, %{
        filters: filters,
        order_by: [sort_field(sort_by)],
        order_directions: [sort_direction(sort_order)],
        page: page,
        page_size: @page_size,
        commands: socket.assigns.bazel_invocation_commands
      })

    commands = socket.assigns.bazel_invocation_commands

    {:noreply,
     socket
     |> assign(:uri, uri)
     |> assign(:invocations, invocations)
     |> assign(:current_page, meta.current_page)
     |> assign(:total_pages, meta.total_pages)
     |> assign(:invocations_sort_by, sort_by)
     |> assign(:invocations_sort_order, sort_order)
     |> assign(:analytics_preset, analytics_preset)
     |> assign(:analytics_period, analytics_period)
     |> assign(:analytics_trend_label, analytics_trend_label(analytics_preset))
     |> assign(:analytics_selected_widget, analytics_selected_widget)
     |> assign(:selected_duration_type, params["duration-type"] || "avg")
     |> assign(:active_filters, active_filters)
     |> assign_async([:invocation_summary, :invocation_analytics], fn ->
       {:ok,
        %{
          invocation_summary:
            invocation_summary_with_trends(
              project.id,
              analytics_period,
              commands
            ),
          invocation_analytics:
            Bazel.invocation_analytics(
              project.id,
              period_opts(analytics_period, commands)
            )
        }}
     end)}
  end

  def handle_event("select_duration_type", %{"type" => type}, socket) do
    query_params =
      socket.assigns.uri.query
      |> Query.put("duration-type", type)
      |> Query.put("analytics-selected-widget", "build-duration")

    {:noreply, push_patch(socket, to: invocation_list_path(socket, URI.decode_query(query_params)))}
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
      <.card
        title={dgettext("dashboard_projects", "Analytics")}
        icon="chart_arcs"
        data-part="bazel-invocation-analytics-card"
      >
        <:actions>
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
        </:actions>
        <div data-part="widgets">
          <.widget
            id="bazel-total-invocations"
            loading={!@invocation_summary.ok?}
            title={metric_title(@bazel_resource, :total)}
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
            title={metric_title(@bazel_resource, :success_rate)}
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
            title={metric_title(@bazel_resource, :failed)}
            legend_color="destructive"
            description={
              dgettext("dashboard_projects", "Completed commands with a nonzero exit code.")
            }
            value={if @invocation_summary.ok?, do: @invocation_summary.result.failed}
            trend_value={if @invocation_summary.ok?, do: @invocation_summary.result.failed_trend}
            trend_label={@analytics_trend_label}
            trend_type={:inverse}
            phx_click="select_widget"
            phx_value_widget="failed-builds"
            selected={@analytics_selected_widget == "failed-builds"}
          />
          <.percentile_dropdown_widget
            id="bazel-invocation-duration"
            loading={!@invocation_summary.ok?}
            title={duration_title(@selected_duration_type, @bazel_resource)}
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
                @analytics_preset
              )
            }
            series={analytics_chart_series(@invocation_analytics.result, @analytics_selected_widget)}
            y_axis_min={0}
            y_axis_max={if @analytics_selected_widget == "build-success-rate", do: 100}
          />
        </.card_section>
      </.card>
      <.card
        title={@bazel_resource}
        icon="subtask"
        data-part="bazel-invocations-card"
      >
        <.card_section data-part="bazel-invocations-table-section">
          <div data-part="filters">
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
              <:col :let={invocation} label={dgettext("dashboard_projects", "Targets")}>
                <.text_cell label={target_patterns_label(invocation.target_patterns)} />
              </:col>
              <:col
                :let={invocation}
                :if={@bazel_base_path != "builds"}
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
                label={dgettext("dashboard_projects", "Finished")}
                patch={column_patch_sort(assigns, "finished-at")}
                sort_order={@invocations_sort_by == "finished-at" && @invocations_sort_order}
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
            title={empty_state_title(@bazel_resource)}
            get_started_href="https://tuist.dev/en/docs/guides/features/cache/bazel-cache"
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

  defp parse_page(value) do
    case Integer.parse(value || "1") do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp success_rate(summary) do
    if numeric(summary.total) == 0, do: nil, else: "#{Float.round(success_rate_value(summary), 1)}%"
  end

  defp invocation_summary_with_trends(project_id, {start_datetime, end_datetime} = period, commands) do
    summary = Bazel.summary(project_id, period_opts(period, commands))
    previous_summary = Bazel.summary(project_id, period_opts(previous_period(start_datetime, end_datetime), commands))

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

  defp period_opts({start_datetime, end_datetime}, commands),
    do: [start_datetime: start_datetime, end_datetime: end_datetime, commands: commands]

  defp previous_period(start_datetime, end_datetime) do
    duration = DateTime.diff(end_datetime, start_datetime, :second)
    {DateTime.add(start_datetime, -duration, :second), start_datetime}
  end

  defp success_rate_value(summary) do
    total = numeric(summary.total)
    if total == 0, do: 0.0, else: numeric(summary.successful) / total * 100
  end

  defp trend(previous_value, current_value) do
    previous_value = numeric(previous_value)
    current_value = numeric(current_value)

    if previous_value == 0 or current_value == 0 do
      0.0
    else
      Float.round((current_value - previous_value) / previous_value * 100, 1)
    end
  end

  defp analytics_trend_label("last-24-hours"), do: dgettext("dashboard_projects", "since yesterday")
  defp analytics_trend_label("last-7-days"), do: dgettext("dashboard_projects", "since last week")
  defp analytics_trend_label("last-12-months"), do: dgettext("dashboard_projects", "since last year")
  defp analytics_trend_label("custom"), do: dgettext("dashboard_projects", "since last period")
  defp analytics_trend_label(_), do: dgettext("dashboard_projects", "since last month")

  defp date_picker_presets do
    [
      %{id: "last-24-hours", label: dgettext("dashboard_projects", "Last 24 hours"), period: {24, :hour}},
      %{id: "last-7-days", label: dgettext("dashboard_projects", "Last 7 days"), period: {7, :day}},
      %{id: "last-30-days", label: dgettext("dashboard_projects", "Last 30 days"), period: {30, :day}},
      %{id: "last-12-months", label: dgettext("dashboard_projects", "Last 12 months"), period: {12, :month}},
      %{id: "custom", label: dgettext("dashboard_projects", "Custom")}
    ]
  end

  defp metric_title("Builds", :total), do: dgettext("dashboard_projects", "Total builds")
  defp metric_title("Builds", :success_rate), do: dgettext("dashboard_projects", "Build success rate")
  defp metric_title("Builds", :failed), do: dgettext("dashboard_projects", "Failed builds")
  defp metric_title(_, :total), do: dgettext("dashboard_projects", "Total invocations")
  defp metric_title(_, :success_rate), do: dgettext("dashboard_projects", "Invocation success rate")
  defp metric_title(_, :failed), do: dgettext("dashboard_projects", "Failed invocations")

  defp duration_title("p99", "Builds"), do: dgettext("dashboard_projects", "p99 build duration")
  defp duration_title("p90", "Builds"), do: dgettext("dashboard_projects", "p90 build duration")
  defp duration_title("p50", "Builds"), do: dgettext("dashboard_projects", "p50 build duration")
  defp duration_title(_, "Builds"), do: dgettext("dashboard_projects", "Average build duration")
  defp duration_title("p99", _), do: dgettext("dashboard_projects", "p99 invocation duration")
  defp duration_title("p90", _), do: dgettext("dashboard_projects", "p90 invocation duration")
  defp duration_title("p50", _), do: dgettext("dashboard_projects", "p50 invocation duration")
  defp duration_title(_, _), do: dgettext("dashboard_projects", "Average invocation duration")

  defp empty_state_title("Builds"), do: dgettext("dashboard_projects", "No Bazel builds have been received yet.")
  defp empty_state_title(_), do: dgettext("dashboard_projects", "No Bazel invocations have been received yet.")

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

  defp analytics_has_data?(analytics, "total-builds"), do: Enum.any?(analytics.total_values, &(numeric(&1) != 0))

  defp analytics_has_data?(analytics, "build-success-rate"),
    do: Enum.any?(analytics.success_rate_values, &(numeric(&1) != 0))

  defp analytics_has_data?(analytics, "failed-builds"), do: Enum.any?(analytics.failed_values, &(numeric(&1) != 0))

  defp analytics_has_data?(analytics, _), do: Enum.any?(analytics.average_duration_values, &(numeric(&1) != 0))

  defp analytics_chart_options(dates, "build-duration", preset) do
    %{
      legend: chart_legend(),
      grid: %{width: "97%", left: "0.4%", height: "60%", top: "10%"},
      xAxis: chart_x_axis(dates),
      yAxis: chart_y_axis("fn:formatMilliseconds"),
      tooltip: chart_tooltip("fn:formatMilliseconds", preset)
    }
  end

  defp analytics_chart_options(dates, "build-success-rate", preset) do
    %{
      grid: %{width: "97%", left: "0.4%", height: "88%", top: "5%"},
      xAxis: chart_x_axis(dates),
      yAxis: chart_y_axis("{value}%"),
      legend: %{show: false},
      tooltip: chart_tooltip("{value}%", preset)
    }
  end

  defp analytics_chart_options(dates, _widget, preset) do
    %{
      grid: %{width: "97%", left: "0.4%", height: "88%", top: "5%"},
      xAxis: chart_x_axis(dates),
      yAxis: chart_y_axis("{value}"),
      legend: %{show: false},
      tooltip: chart_tooltip("{value}", preset)
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

  defp chart_x_axis(dates) do
    %{
      boundaryGap: false,
      type: "category",
      axisLabel: %{
        color: "var:noora-surface-label-secondary",
        formatter: "fn:toLocaleDate",
        customValues: [List.first(dates), List.last(dates)],
        padding: [10, 0, 0, 0]
      }
    }
  end

  defp chart_y_axis(formatter) do
    %{
      splitNumber: 4,
      splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}},
      axisLabel: %{color: "var:noora-surface-label-secondary", formatter: formatter}
    }
  end

  defp chart_tooltip(value_format, "last-24-hours"), do: %{valueFormat: value_format, dateFormat: "hour"}
  defp chart_tooltip(value_format, _preset), do: %{valueFormat: value_format}

  defp numeric(%Decimal{} = value), do: Decimal.to_float(value)
  defp numeric(value) when is_number(value), do: value
  defp numeric(nil), do: 0

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

  defp invocation_detail_path(%{bazel_base_path: "builds"} = assigns, invocation_id) do
    ~p"/#{assigns.selected_account.name}/#{assigns.selected_project.name}/builds/invocations/#{invocation_id}"
  end

  defp invocation_detail_path(assigns, invocation_id) do
    ~p"/#{assigns.selected_account.name}/#{assigns.selected_project.name}/invocations/#{invocation_id}"
  end

  defp sort_field("command"), do: :command
  defp sort_field("status"), do: :status
  defp sort_field("duration"), do: :duration_ms
  defp sort_field(_), do: :finished_at

  defp sort_direction("asc"), do: :asc
  defp sort_direction(_), do: :desc

  defp target_patterns_label([]), do: dgettext("dashboard_projects", "No targets reported")

  defp target_patterns_label([first_target | remaining_targets]) do
    case length(remaining_targets) do
      0 -> first_target
      count -> "#{first_target} +#{count}"
    end
  end

  defp define_filters do
    [
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
      },
      %Filter.Filter{
        id: "command",
        field: :command,
        display_name: dgettext("dashboard_projects", "Command"),
        type: :text,
        operator: :=~,
        value: ""
      }
    ]
  end
end
