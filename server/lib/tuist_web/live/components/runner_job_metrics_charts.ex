defmodule TuistWeb.Components.RunnerJobMetricsCharts do
  @moduledoc """
  Renders the machine-metrics charts for a runner job: CPU, Memory,
  Network, CPU I/O Wait and Storage time series.

  Two entry points share the same data prep:

    * `runner_job_metrics_charts/1` — the full five-chart grid shown
      on the job's Metrics tab.
    * `runner_job_metrics_overview/1` — a compact CPU / Memory /
      Network row shown above the Steps card on the Overview tab,
      where hovering a step shades the matching time range across the
      charts (driven by the `RunnerMetricsHighlight` JS hook).

  Series are emitted as `[epoch_ms, value]` pairs on a time x-axis so
  the highlight overlay can address an arbitrary step window by
  timestamp instead of snapping to a sample index.
  """
  use TuistWeb, :html
  use Noora

  attr :id, :string, default: "runner-job-metrics"
  attr :metrics, :list, required: true

  def runner_job_metrics_charts(assigns) do
    assigns = assign(assigns, :series, build_series(assigns.metrics))

    ~H"""
    <div class="tuist-runner-metrics" data-metrics-charts>
      <.card icon="chart_dots" title={dgettext("dashboard_runners", "Metrics")}>
        <.card_section data-part="charts-grid">
          <.metric_chart
            id={"#{@id}-cpu"}
            title="CPU"
            series={[%{name: dgettext("dashboard_runners", "Usage"), values: @series.cpu}]}
            y_max={100}
            unit="%"
          />
          <.metric_chart
            id={"#{@id}-memory"}
            title="Memory"
            series={[%{name: dgettext("dashboard_runners", "Used"), values: @series.memory}]}
            y_max={@series.memory_total_gb}
            unit=" GB"
          />
          <.metric_chart
            id={"#{@id}-network"}
            title="Network"
            series={[
              %{name: dgettext("dashboard_runners", "In"), values: @series.network_in},
              %{name: dgettext("dashboard_runners", "Out"), values: @series.network_out}
            ]}
            unit=" MiB"
            show_legend
          />
          <.metric_chart
            id={"#{@id}-iowait"}
            title={dgettext("dashboard_runners", "CPU I/O Wait")}
            series={[%{name: dgettext("dashboard_runners", "Wait"), values: @series.iowait}]}
            y_max={100}
            unit="%"
          />
          <.metric_chart
            id={"#{@id}-storage"}
            title={dgettext("dashboard_runners", "Storage")}
            series={[%{name: dgettext("dashboard_runners", "Used"), values: @series.storage}]}
            y_max={100}
            unit="%"
          />
        </.card_section>
      </.card>
    </div>
    """
  end

  attr :id, :string, default: "runner-job-metrics-overview"
  attr :metrics, :list, required: true

  def runner_job_metrics_overview(assigns) do
    assigns = assign(assigns, :series, build_series(assigns.metrics))

    ~H"""
    <div class="tuist-runner-metrics" data-part="overview" data-metrics-charts>
      <.card_section data-part="charts-grid">
        <.metric_chart
          id={"#{@id}-cpu"}
          title="CPU"
          series={[%{name: dgettext("dashboard_runners", "Usage"), values: @series.cpu}]}
          y_max={100}
          unit="%"
        />
        <.metric_chart
          id={"#{@id}-memory"}
          title="Memory"
          series={[%{name: dgettext("dashboard_runners", "Used"), values: @series.memory}]}
          y_max={@series.memory_total_gb}
          unit=" GB"
        />
        <.metric_chart
          id={"#{@id}-network"}
          title="Network"
          series={[
            %{name: dgettext("dashboard_runners", "In"), values: @series.network_in},
            %{name: dgettext("dashboard_runners", "Out"), values: @series.network_out}
          ]}
          unit=" MiB"
          show_legend
        />
      </.card_section>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :series, :list, required: true
  attr :unit, :string, required: true
  attr :y_max, :any, default: nil
  attr :show_legend, :boolean, default: false

  defp metric_chart(assigns) do
    ~H"""
    <.card_section data-part="chart-card">
      <span data-part="chart-title">{@title}</span>
      <.chart
        id={@id}
        type="line"
        smooth={0.1}
        series={@series}
        colors={["var:noora-chart-primary", "var:noora-chart-secondary"]}
        show_legend={false}
        extra_options={chart_options(assigns)}
      />
    </.card_section>
    """
  end

  # Common ECharts options for every metric chart. The x-axis is a
  # time axis so the `RunnerMetricsHighlight` hook can place a
  # `markArea` at the hovered step's `[start, end]` window directly.
  defp chart_options(assigns) do
    y_axis =
      maybe_put(
        %{
          min: 0,
          splitNumber: 4,
          splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}},
          axisLabel: %{color: "var:noora-surface-label-secondary", formatter: "{value}#{assigns.unit}"}
        },
        :max,
        assigns.y_max
      )

    maybe_put_legend(
      %{
        grid: %{left: "3%", right: "8%", bottom: bottom_padding(assigns.show_legend), top: "8%", containLabel: true},
        xAxis: %{
          type: "time",
          boundaryGap: false,
          axisLabel: %{
            color: "var:noora-surface-label-secondary",
            customValues: label_values(assigns.series),
            hideOverlap: true,
            padding: [10, 0, 0, 0],
            formatter: "fn:toLocaleTime"
          }
        },
        yAxis: y_axis,
        tooltip: %{valueFormat: "{value}#{assigns.unit}", dateFormat: "minute"}
      },
      assigns.show_legend
    )
  end

  defp bottom_padding(true), do: "25%"
  defp bottom_padding(false), do: "10%"

  # Pin the time axis to just its endpoints so labels never crowd or
  # overlap in the narrow chart cards (matches the build-metrics charts).
  defp label_values(series) do
    series
    |> Enum.flat_map(fn s -> Enum.map(s.values, &hd/1) end)
    |> case do
      [] -> []
      timestamps -> [Enum.min(timestamps), Enum.max(timestamps)]
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_legend(options, false), do: options

  defp maybe_put_legend(options, true) do
    Map.put(options, :legend, %{
      left: "left",
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
      itemHeight: 4,
      itemGap: 16
    })
  end

  # Collapses samples sharing a whole-second timestamp (the collector
  # may emit more than one per second) to the last reading, then maps
  # each metric into `[epoch_ms, value]` pairs for the time axis.
  defp build_series(metrics) do
    points =
      metrics
      |> Enum.group_by(fn m -> trunc(m.timestamp) end)
      |> Enum.sort_by(fn {second, _} -> second end)
      |> Enum.map(fn {_, samples} -> List.last(samples) end)

    %{
      cpu: line(points, fn m -> round1(m.cpu_usage_percent) end),
      iowait: line(points, fn m -> round1(m.cpu_iowait_percent) end),
      memory: line(points, fn m -> bytes_to_gb(m.memory_used_bytes) end),
      memory_total_gb: memory_total_gb(points),
      network_in: line(points, fn m -> bytes_to_mib(m.network_bytes_in) end),
      network_out: line(points, fn m -> bytes_to_mib(m.network_bytes_out) end),
      storage: line(points, fn m -> percentage(m.disk_used_bytes, m.disk_total_bytes) end)
    }
  end

  defp line(points, value_fun) do
    Enum.map(points, fn m -> [epoch_ms(m.timestamp), value_fun.(m)] end)
  end

  defp memory_total_gb([]), do: 0
  defp memory_total_gb([first | _]), do: bytes_to_gb(first.memory_total_bytes)

  defp epoch_ms(timestamp), do: trunc(timestamp * 1000)

  defp round1(value), do: Float.round(value + 0.0, 1)

  defp bytes_to_gb(bytes), do: Float.round(bytes / (1000 * 1000 * 1000), 1)

  defp bytes_to_mib(bytes), do: Float.round(bytes / (1024 * 1024), 2)

  defp percentage(_used, total) when total in [nil, 0], do: 0.0
  defp percentage(used, total), do: Float.round(used / total * 100, 1)
end
