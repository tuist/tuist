defmodule TuistWeb.BazelTestsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.Skeleton
  import TuistWeb.PercentileDropdownWidget

  alias Noora.Filter
  alias Tuist.Bazel
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  @page_size 20

  def assign_mount(%{assigns: %{selected_project: project, selected_account: account}} = socket) do
    socket
    |> assign(:head_title, "#{dgettext("dashboard_tests", "Tests")} · #{account.name}/#{project.name} · Tuist")
    |> assign(OpenGraph.og_image_assigns("tests"))
    |> assign(:available_filters, define_filters())
  end

  def assign_handle_params(%{assigns: %{selected_project: project}} = socket, params) do
    page = parse_page(params["page"])
    sort_by = params["tests-sort-by"] || "finished-at"
    sort_order = params["tests-sort-order"] || "desc"
    uri = URI.new!("?" <> URI.encode_query(params))

    %{preset: analytics_preset, period: analytics_period} =
      DatePicker.date_picker_params(params, "analytics")

    analytics_selected_widget = params["analytics-selected-widget"] || "test-duration"
    active_filters = Filter.Operations.decode_filters_from_query(params, socket.assigns.available_filters)

    filters =
      [%{field: :project_id, op: :==, value: project.id}] ++
        Filter.Operations.convert_filters_to_flop(active_filters)

    {test_results, meta} =
      Bazel.list_test_results(project.id, %{
        filters: filters,
        order_by: [sort_field(sort_by)],
        order_directions: [sort_direction(sort_order)],
        page: page,
        page_size: @page_size
      })

    socket
    |> assign(:uri, uri)
    |> assign(:test_results, test_results)
    |> assign(:current_page, meta.current_page)
    |> assign(:total_pages, meta.total_pages)
    |> assign(:tests_sort_by, sort_by)
    |> assign(:tests_sort_order, sort_order)
    |> assign(:active_filters, active_filters)
    |> assign(:analytics_preset, analytics_preset)
    |> assign(:analytics_period, analytics_period)
    |> assign(:analytics_trend_label, analytics_trend_label(analytics_preset))
    |> assign(:analytics_selected_widget, analytics_selected_widget)
    |> assign(:selected_duration_type, params["duration-type"] || "avg")
    |> assign_async([:test_summary, :test_analytics], fn ->
      {:ok,
       %{
         test_summary: test_summary_with_trends(project.id, analytics_period),
         test_analytics: Bazel.test_analytics(project.id, period_opts(analytics_period))
       }}
    end)
  end

  def handle_event("select_duration_type", %{"type" => type}, socket) do
    query_params =
      socket.assigns.uri.query
      |> Query.put("duration-type", type)
      |> Query.put("analytics-selected-widget", "test-duration")

    {:noreply, push_patch(socket, to: tests_path(socket, URI.decode_query(query_params)))}
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

    {:noreply, push_patch(socket, to: tests_path(socket, URI.decode_query(query_params)))}
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params =
      filter_id
      |> Filter.Operations.add_filter_to_query(socket)
      |> Map.put("page", "1")

    socket
    |> push_patch(to: tests_path(socket, updated_params))
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
    |> push_patch(to: tests_path(socket, updated_params))
    |> push_event("close-dropdown", %{id: "all", all: true})
    |> push_event("close-popover", %{id: "all", all: true})
    |> then(&{:noreply, &1})
  end

  def render(assigns) do
    ~H"""
    <div id="bazel-tests" class="bazel-invocations">
      <.card
        title={dgettext("dashboard_projects", "Analytics")}
        icon="chart_arcs"
        data-part="bazel-tests-analytics-card"
      >
        <:actions>
          <.date_picker
            id="bazel-tests-date-range-picker"
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
                    detail: %{id: "bazel-tests-date-range-picker"}
                  )
                }
              />
              <.button
                label={dgettext("dashboard_projects", "Apply")}
                phx-click={
                  JS.dispatch("phx:date-picker-apply", detail: %{id: "bazel-tests-date-range-picker"})
                }
              />
            </:actions>
          </.date_picker>
        </:actions>
        <div data-part="widgets">
          <.widget
            id="bazel-total-tests"
            loading={!@test_summary.ok?}
            title={dgettext("dashboard_projects", "Total tests")}
            legend_color="primary"
            description={
              dgettext("dashboard_projects", "Completed Bazel test targets in the selected period.")
            }
            value={if @test_summary.ok?, do: @test_summary.result.total}
            trend_value={if @test_summary.ok?, do: @test_summary.result.total_trend}
            trend_label={@analytics_trend_label}
            empty={@test_summary.ok? && @test_summary.result.total == 0}
            phx_click="select_widget"
            phx_value_widget="total-tests"
            selected={@analytics_selected_widget == "total-tests"}
          />
          <.widget
            id="bazel-test-success-rate"
            loading={!@test_summary.ok?}
            title={dgettext("dashboard_projects", "Test success rate")}
            legend_color="primary"
            description={
              dgettext(
                "dashboard_projects",
                "The share of test targets Bazel completed successfully."
              )
            }
            value={if @test_summary.ok?, do: success_rate(@test_summary.result)}
            trend_value={if @test_summary.ok?, do: @test_summary.result.success_rate_trend}
            trend_label={@analytics_trend_label}
            empty={@test_summary.ok? && @test_summary.result.total == 0}
            phx_click="select_widget"
            phx_value_widget="test-success-rate"
            selected={@analytics_selected_widget == "test-success-rate"}
          />
          <.widget
            id="bazel-failed-tests"
            loading={!@test_summary.ok?}
            title={dgettext("dashboard_projects", "Failed tests")}
            legend_color="destructive"
            description={
              dgettext("dashboard_projects", "Test targets whose final Bazel status was a failure.")
            }
            value={if @test_summary.ok?, do: @test_summary.result.failed}
            trend_value={if @test_summary.ok?, do: @test_summary.result.failed_trend}
            trend_label={@analytics_trend_label}
            trend_type={:inverse}
            phx_click="select_widget"
            phx_value_widget="failed-tests"
            selected={@analytics_selected_widget == "failed-tests"}
          />
          <.percentile_dropdown_widget
            id="bazel-test-duration"
            loading={!@test_summary.ok?}
            title={duration_title(@selected_duration_type)}
            description={
              dgettext(
                "dashboard_projects",
                "The runtime of completed Bazel test targets, with average and percentile views."
              )
            }
            value={
              if @test_summary.ok?,
                do:
                  DateFormatter.format_duration_from_milliseconds(
                    duration_value(@test_summary.result, @selected_duration_type)
                  )
            }
            metrics={if @test_summary.ok?, do: duration_metrics(@test_summary.result)}
            selected_type={@selected_duration_type}
            event_name="select_duration_type"
            phx_click="select_widget"
            phx_value_widget="test-duration"
            selected={@analytics_selected_widget == "test-duration"}
            trend_value={
              if @test_summary.ok?, do: duration_trend(@test_summary.result, @selected_duration_type)
            }
            trend_label={@analytics_trend_label}
            trend_type={:inverse}
            empty={@test_summary.ok? && @test_summary.result.total == 0}
          />
        </div>
        <.card_section :if={!@test_analytics.ok?} data-part="analytics-card-chart-section">
          <.skeleton_chart />
        </.card_section>
        <.card_section
          :if={
            @test_analytics.ok? &&
              analytics_has_data?(@test_analytics.result, @analytics_selected_widget)
          }
          data-part="analytics-card-chart-section"
        >
          <.chart
            id="bazel-tests-analytics-chart"
            type="line"
            extra_options={
              analytics_chart_options(
                @test_analytics.result.dates,
                @analytics_selected_widget,
                @analytics_preset
              )
            }
            series={analytics_chart_series(@test_analytics.result, @analytics_selected_widget)}
            y_axis_min={0}
            y_axis_max={if @analytics_selected_widget == "test-success-rate", do: 100}
          />
        </.card_section>
      </.card>

      <.card title={dgettext("dashboard_tests", "Tests")} icon="subtask">
        <.card_section>
          <div data-part="filters">
            <.filter_dropdown
              id="bazel-tests-filter-dropdown"
              label={dgettext("dashboard_projects", "Filter")}
              available_filters={@available_filters}
              active_filters={@active_filters}
            />
          </div>
          <div :if={Enum.any?(@active_filters)} data-part="active-filters">
            <.active_filter :for={filter <- @active_filters} filter={filter} />
          </div>
          <div :if={Enum.any?(@test_results)} data-part="bazel-tests-table">
            <.table
              id="bazel-tests-table"
              rows={@test_results}
              row_navigate={
                fn test_result ->
                  url(
                    ~p"/#{@selected_account.name}/#{@selected_project.name}/tests/test-results/#{test_result.id}"
                  )
                end
              }
            >
              <:col
                :let={test_result}
                label={dgettext("dashboard_projects", "Target")}
                patch={column_patch_sort(assigns, "target")}
                sort_order={@tests_sort_by == "target" && @tests_sort_order}
              >
                <.text_cell label={test_result.target_label} />
              </:col>
              <:col
                :let={test_result}
                label={dgettext("dashboard_projects", "Status")}
                patch={column_patch_sort(assigns, "status")}
                sort_order={@tests_sort_by == "status" && @tests_sort_order}
              >
                <.status_badge_cell
                  label={status_label(test_result.status)}
                  status={test_status_badge(test_result.status)}
                />
              </:col>
              <:col
                :let={test_result}
                label={dgettext("dashboard_projects", "Duration")}
                patch={column_patch_sort(assigns, "duration")}
                sort_order={@tests_sort_by == "duration" && @tests_sort_order}
              >
                <.text_cell
                  label={DateFormatter.format_duration_from_milliseconds(test_result.duration_ms)}
                  icon="history"
                />
              </:col>
              <:col
                :let={test_result}
                label={dgettext("dashboard_projects", "Attempts")}
                patch={column_patch_sort(assigns, "attempts")}
                sort_order={@tests_sort_by == "attempts" && @tests_sort_order}
              >
                <.text_cell label={test_result.attempt_count} />
              </:col>
              <:col
                :let={test_result}
                label={dgettext("dashboard_projects", "Invocation")}
                patch={column_patch_sort(assigns, "invocation")}
                sort_order={@tests_sort_by == "invocation" && @tests_sort_order}
              >
                <.text_cell label={test_result.invocation_id} />
              </:col>
              <:col
                :let={test_result}
                label={dgettext("dashboard_projects", "Finished")}
                patch={column_patch_sort(assigns, "finished-at")}
                sort_order={@tests_sort_by == "finished-at" && @tests_sort_order}
              >
                <.text_cell sublabel={DateFormatter.from_now(test_result.finished_at)} />
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
            :if={Enum.empty?(@test_results)}
            title={dgettext("dashboard_projects", "No Bazel test results have been received yet.")}
            get_started_href="https://tuist.dev/en/docs/guides/features/cache/bazel-cache"
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

  defp test_summary_with_trends(project_id, {start_datetime, end_datetime}) do
    summary = Bazel.test_summary(project_id, period_opts({start_datetime, end_datetime}))

    previous_summary =
      Bazel.test_summary(project_id, period_opts(previous_period(start_datetime, end_datetime)))

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

  defp period_opts({start_datetime, end_datetime}), do: [start_datetime: start_datetime, end_datetime: end_datetime]

  defp previous_period(start_datetime, end_datetime) do
    duration = DateTime.diff(end_datetime, start_datetime, :second)
    {DateTime.add(start_datetime, -duration, :second), start_datetime}
  end

  defp success_rate(summary) do
    if numeric(summary.total) == 0, do: nil, else: "#{Float.round(success_rate_value(summary), 1)}%"
  end

  defp success_rate_value(summary) do
    total = numeric(summary.total)
    if total == 0, do: 0.0, else: numeric(summary.successful) / total * 100
  end

  defp trend(previous_value, current_value) do
    previous_value = numeric(previous_value)
    current_value = numeric(current_value)

    if previous_value == 0 or current_value == 0,
      do: 0.0,
      else: Float.round((current_value - previous_value) / previous_value * 100, 1)
  end

  defp duration_title("p99"), do: dgettext("dashboard_projects", "p99 test duration")
  defp duration_title("p90"), do: dgettext("dashboard_projects", "p90 test duration")
  defp duration_title("p50"), do: dgettext("dashboard_projects", "p50 test duration")
  defp duration_title(_), do: dgettext("dashboard_projects", "Average test duration")
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

  defp analytics_has_data?(analytics, "total-tests"), do: Enum.any?(analytics.total_values, &(numeric(&1) != 0))

  defp analytics_has_data?(analytics, "test-success-rate"),
    do: Enum.any?(analytics.success_rate_values, &(numeric(&1) != 0))

  defp analytics_has_data?(analytics, "failed-tests"), do: Enum.any?(analytics.failed_values, &(numeric(&1) != 0))

  defp analytics_has_data?(analytics, _), do: Enum.any?(analytics.average_duration_values, &(numeric(&1) != 0))

  defp analytics_chart_options(dates, "test-duration", preset) do
    %{
      legend: chart_legend(),
      grid: %{width: "97%", left: "0.4%", height: "60%", top: "10%"},
      xAxis: chart_x_axis(dates),
      yAxis: chart_y_axis("fn:formatMilliseconds"),
      tooltip: chart_tooltip("fn:formatMilliseconds", preset)
    }
  end

  defp analytics_chart_options(dates, "test-success-rate", preset) do
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

  defp analytics_chart_series(analytics, "total-tests") do
    [
      chart_series(
        analytics.dates,
        analytics.total_values,
        "var:noora-chart-primary",
        dgettext("dashboard_projects", "Completed tests")
      )
    ]
  end

  defp analytics_chart_series(analytics, "test-success-rate") do
    [
      chart_series(
        analytics.dates,
        analytics.success_rate_values,
        "var:noora-chart-primary",
        dgettext("dashboard_projects", "Test success rate")
      )
    ]
  end

  defp analytics_chart_series(analytics, "failed-tests") do
    [
      chart_series(
        analytics.dates,
        analytics.failed_values,
        "var:noora-chart-destructive",
        dgettext("dashboard_projects", "Failed tests")
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

  defp status_label("success"), do: dgettext("dashboard_projects", "Succeeded")
  defp status_label("flaky"), do: dgettext("dashboard_projects", "Flaky")
  defp status_label("skipped"), do: dgettext("dashboard_projects", "Skipped")
  defp status_label(_), do: dgettext("dashboard_projects", "Failed")
  defp test_status_badge("success"), do: "success"
  defp test_status_badge("flaky"), do: "warning"
  defp test_status_badge("skipped"), do: "attention"
  defp test_status_badge(_), do: "error"
  defp numeric(%Decimal{} = value), do: Decimal.to_float(value)
  defp numeric(value) when is_number(value), do: value
  defp numeric(nil), do: 0

  defp parse_page(value) do
    case Integer.parse(value || "1") do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp sort_field("target"), do: :target_label
  defp sort_field("status"), do: :status
  defp sort_field("duration"), do: :duration_ms
  defp sort_field("attempts"), do: :attempt_count
  defp sort_field("invocation"), do: :invocation_id
  defp sort_field(_), do: :finished_at
  defp sort_direction("asc"), do: :asc
  defp sort_direction(_), do: :desc
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

  defp column_patch_sort(%{uri: uri, tests_sort_by: sort_by, tests_sort_order: sort_order}, column_value) do
    next_order = if sort_by == column_value and sort_order == "asc", do: "desc", else: "asc"

    uri.query
    |> URI.decode_query()
    |> Map.put("tests-sort-by", column_value)
    |> Map.put("tests-sort-order", next_order)
    |> Map.put("page", "1")
    |> URI.encode_query()
    |> then(&"?#{&1}")
  end

  defp tests_path(socket, params) do
    "/#{socket.assigns.selected_account.name}/#{socket.assigns.selected_project.name}/tests?#{URI.encode_query(params)}"
  end

  defp define_filters do
    [
      %Filter.Filter{
        id: "status",
        field: :status,
        display_name: dgettext("dashboard_projects", "Status"),
        type: :option,
        options: ["success", "failure", "flaky", "skipped"],
        options_display_names: %{
          "success" => dgettext("dashboard_projects", "Succeeded"),
          "failure" => dgettext("dashboard_projects", "Failed"),
          "flaky" => dgettext("dashboard_projects", "Flaky"),
          "skipped" => dgettext("dashboard_projects", "Skipped")
        },
        operator: :==,
        value: nil
      },
      %Filter.Filter{
        id: "target",
        field: :target_label,
        display_name: dgettext("dashboard_projects", "Target"),
        type: :text,
        operator: :=~,
        value: ""
      },
      %Filter.Filter{
        id: "invocation",
        field: :invocation_id,
        display_name: dgettext("dashboard_projects", "Invocation"),
        type: :text,
        operator: :=~,
        value: ""
      }
    ]
  end
end
