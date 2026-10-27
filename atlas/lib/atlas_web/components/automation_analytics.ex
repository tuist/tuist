defmodule AtlasWeb.AutomationAnalytics do
  @moduledoc false

  use Phoenix.Component
  use Noora
  use Gettext, backend: AtlasWeb.Gettext

  import AtlasWeb.Components.EmptyCardSection
  import AtlasWeb.Components.Skeleton, only: [skeleton_chart: 1]
  import AtlasWeb.Widget

  alias Phoenix.LiveView.JS

  attr :analytics, :any, required: true
  attr :metric, :string, required: true
  attr :days, :integer, required: true

  attr :end_date, :any, default: nil
  attr :preset, :string, default: nil

  def execution_overview(assigns) do
    until = assigns.end_date || Date.utc_today()
    first = Date.add(until, 1 - assigns.days)

    assigns =
      assigns
      |> assign(:ready, assigns.analytics.ok?)
      |> assign(:period, {DateTime.new!(first, ~T[00:00:00]), DateTime.new!(until, ~T[23:59:59])})
      |> assign(:preset, assigns.preset || "last-#{assigns.days}-days")

    ~H"""
    <div data-part="analytics-filters">
      <.date_picker
        id="automation-analytics-period"
        name="analytics-date-range"
        presets={[
          %{id: "last-7-days", label: gettext("Last %{days} days", days: 7), period: {7, :day}},
          %{id: "last-30-days", label: gettext("Last %{days} days", days: 30), period: {30, :day}},
          %{id: "last-90-days", label: gettext("Last %{days} days", days: 90), period: {90, :day}},
          %{id: "custom", label: gettext("Custom")}
        ]}
        selected_preset={@preset}
        period={@period}
        on_period_change="analytics_period_changed"
        max={Date.utc_today()}
      >
        <:actions>
          <.button
            label={gettext("Cancel")}
            variant="secondary"
            phx-click={
              JS.dispatch("phx:date-picker-cancel", detail: %{id: "automation-analytics-period"})
            }
          />
          <.button
            label={gettext("Apply")}
            phx-click={
              JS.dispatch("phx:date-picker-apply", detail: %{id: "automation-analytics-period"})
            }
          />
        </:actions>
      </.date_picker>
    </div>
    <.card
      id="automation-analytics"
      title={gettext("Analytics")}
      icon="chart_arcs"
      data-part="execution-overview"
      data-state={
        cond do
          @analytics.failed -> "failed"
          !@ready -> "loading"
          @analytics.loading -> "refreshing"
          true -> "ready"
        end
      }
      aria-busy={if @analytics.loading, do: "true", else: "false"}
    >
      <%= if @analytics.failed do %>
        <.card_section data-part="analytics-error">
          <p>
            {gettext(
              "Execution metrics could not be loaded. Your workflows and execution history are still available."
            )}
          </p>
          <.button
            label={gettext("Retry")}
            variant="secondary"
            size="small"
            phx-click="retry_analytics"
          />
        </.card_section>
      <% else %>
        <div data-part="analytics-content">
          <div data-part="widgets">
            <.widget
              :for={metric <- metrics()}
              id={"automation-metric-#{metric.id}"}
              variant="analytics"
              title={metric.title}
              tooltip_description={metric.description}
              value={if @ready, do: metric_value(@analytics.result.total, metric.id)}
              legend_color={metric.color}
              loading={!@ready}
              empty={@ready && unavailable?(@analytics.result.total, metric.id)}
              empty_label={gettext("No data yet")}
              phx_click="select_analytics_metric"
              phx_value_widget={metric.id}
              selected={@metric == metric.id}
              trend_value={if @ready, do: trend(@analytics.result, metric.id)}
              trend_label={gettext("vs previous %{days} days", days: @days)}
              trend_type={if metric.id == "duration", do: :inverse, else: :neutral}
            />
          </div>
          <.card_section
            :if={!@ready || !unavailable?(@analytics.result.total, @metric)}
            data-chart-frame="compact"
          >
            <%= cond do %>
              <% !@ready -> %>
                <div data-part="analytics-chart"><.skeleton_chart height="200px" /></div>
              <% true -> %>
                <div data-part="analytics-chart" id="automation-analytics-chart-wrapper">
                  <.chart
                    id="automation-execution-chart"
                    data-part="execution-chart"
                    type="line"
                    labels={Enum.map(@analytics.result.points, & &1.date)}
                    series={chart_series(@analytics.result.points, @metric)}
                    extra_options={chart_options(@metric, @analytics.result.points)}
                    y_axis_min={0}
                    y_axis_max={if @metric == "success_rate", do: 100}
                    show_legend={false}
                  />
                </div>
            <% end %>
          </.card_section>
          <.empty_card_section
            :if={@ready && unavailable?(@analytics.result.total, @metric)}
            id="automation-analytics-empty"
            title={gettext("No data yet")}
            data-chart-frame="compact"
          >
            <:image>
              <img
                src="/images/empty_line_chart_light.png"
                data-theme="light"
                loading="lazy"
                decoding="async"
                alt=""
              />
              <img
                src="/images/empty_line_chart_dark.png"
                data-theme="dark"
                loading="lazy"
                decoding="async"
                alt=""
              />
            </:image>
          </.empty_card_section>
        </div>
      <% end %>
    </.card>
    """
  end

  defp metrics do
    [
      %{
        id: "executions",
        title: gettext("Executions"),
        color: "primary",
        description:
          gettext(
            "Executions started in the selected period, across all workflow versions. Retries of the same execution are not counted again."
          )
      },
      %{
        id: "success_rate",
        title: gettext("Success rate"),
        color: "tertiary",
        description:
          gettext(
            "Succeeded executions divided by finished executions. Failed, rejected, and cancelled executions are included; unfinished executions are excluded."
          )
      },
      %{
        id: "duration",
        title: gettext("Avg. completion time"),
        color: "secondary",
        description:
          gettext(
            "Elapsed time from admission to completion, including queueing, retries, and approval waits. Only finished executions with valid timestamps are included."
          )
      },
      %{
        id: "approvals",
        title: gettext("Awaiting approval"),
        color: "flaky",
        description:
          gettext(
            "Executions started in this period that are currently waiting for approval. The chart groups these by start date, not historical approval backlog."
          )
      }
    ]
  end

  defp unavailable?(total, _metric) when total.executions == 0, do: true
  defp unavailable?(total, metric), do: metric_unavailable?(total, metric)
  defp metric_unavailable?(total, "success_rate"), do: is_nil(total.success_rate)
  defp metric_unavailable?(total, "duration"), do: is_nil(total.average_completion_seconds)
  defp metric_unavailable?(_, _), do: false

  defp metric_value(total, "executions"), do: Integer.to_string(total.executions)
  defp metric_value(total, "approvals"), do: Integer.to_string(total.waiting_approval)
  defp metric_value(%{success_rate: nil}, "success_rate"), do: nil
  defp metric_value(total, "success_rate"), do: "#{Float.round(total.success_rate, 1)}%"
  defp metric_value(%{average_completion_seconds: nil}, "duration"), do: nil
  defp metric_value(total, "duration"), do: duration(total.average_completion_seconds)

  defp duration(seconds) when seconds < 1, do: "#{round(seconds * 1000)}ms"
  defp duration(seconds) when seconds < 60, do: "#{round(seconds)}s"
  defp duration(seconds) when seconds < 3600, do: "#{div(round(seconds), 60)}m #{rem(round(seconds), 60)}s"
  defp duration(seconds), do: "#{div(round(seconds), 3600)}h #{div(rem(round(seconds), 3600), 60)}m"

  defp trend(result, "executions"), do: change(result.total.executions, result.previous.executions)

  defp trend(result, "duration"),
    do: change(result.total.average_completion_seconds, result.previous.average_completion_seconds)

  defp trend(_, _), do: nil
  defp change(_, previous) when is_nil(previous) or previous == 0, do: nil
  defp change(nil, _), do: nil
  defp change(current, previous), do: (current - previous) / previous * 100

  defp chart_series(points, "executions"), do: [series(points, :executions, gettext("Executions"), "primary", "line")]

  defp chart_series(points, "success_rate"),
    do: [series(points, :success_rate, gettext("Success rate"), "tertiary", "line")]

  defp chart_series(points, "duration"),
    do: [series(points, :average_completion_seconds, gettext("Avg. completion time"), "secondary", "line")]

  defp chart_series(points, "approvals"),
    do: [series(points, :waiting_approval, gettext("Awaiting approval by start date"), "flaky", "line")]

  defp series(points, field, name, color, type) do
    values = if is_function(field), do: Enum.map(points, field), else: Enum.map(points, &Map.fetch!(&1, field))

    %{
      name: name,
      data: values,
      color: "var:noora-chart-#{color}",
      type: type,
      connectNulls: false,
      smooth: 0.1,
      symbol: if(field in [:success_rate, :average_completion_seconds], do: "circle", else: "none"),
      symbolSize: 4
    }
  end

  defp chart_options(metric, points) do
    format =
      case metric do
        "duration" -> "fn:formatSeconds"
        "success_rate" -> "{value}%"
        _ -> "{value}"
      end

    %{
      grid: %{width: "93%", left: "0.4%", right: "7%", height: "88%", top: "5%"},
      legend: %{show: false},
      xAxis: %{
        boundaryGap: false,
        type: "category",
        axisLabel: %{
          color: "var:noora-surface-label-secondary",
          formatter: "fn:atlasUTCDate",
          interval: 0,
          customValues: [hd(points).date, List.last(points).date],
          padding: [10, 0, 0, 0]
        }
      },
      yAxis: %{
        minInterval: if(metric in ["executions", "approvals"], do: 1, else: 0),
        splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}},
        axisLabel: %{formatter: format, color: "var:noora-surface-label-secondary"}
      },
      tooltip: %{valueFormat: format, dateFormat: "day"}
    }
  end
end
