defmodule TuistWeb.Components.MachineMetricsCharts do
  @moduledoc """
  Shared component for rendering machine metrics charts (CPU, Memory, Network I/O, Disk I/O).
  Used by both Xcode and Gradle build run pages.
  """
  use TuistWeb, :html
  use Noora

  def machine_metrics_charts(assigns) do
    metrics = assigns.metrics

    min_timestamp =
      case metrics do
        [first | _] -> first.timestamp
        _ -> 0.0
      end

    metrics =
      metrics
      |> Enum.group_by(fn m -> trunc(m.timestamp - min_timestamp) end)
      |> Enum.sort_by(fn {k, _} -> k end)
      |> Enum.map(fn {_, samples} -> List.last(samples) end)

    labels = Enum.map(metrics, fn m -> format_time(trunc((m.timestamp - min_timestamp) * 1000)) end)
    cpu_data = Enum.map(metrics, fn m -> Float.round(m.cpu_usage_percent + 0.0, 1) end)
    memory_data = Enum.map(metrics, fn m -> bytes_to_gib(m.memory_used_bytes) end)

    memory_total =
      case metrics do
        [first | _] -> bytes_to_gib(first.memory_total_bytes)
        _ -> 0
      end

    network_in_data = Enum.map(metrics, fn m -> bytes_to_mib(m.network_bytes_in) end)
    network_out_data = Enum.map(metrics, fn m -> bytes_to_mib(m.network_bytes_out) end)
    disk_read_data = Enum.map(metrics, fn m -> bytes_to_mib(m.disk_bytes_read) end)
    disk_write_data = Enum.map(metrics, fn m -> bytes_to_mib(m.disk_bytes_written) end)

    label_count = length(labels)
    label_interval = max(div(label_count, 8) - 1, 0)

    assigns =
      assigns
      |> assign(:labels, labels)
      |> assign(:label_interval, label_interval)
      |> assign(:cpu_data, cpu_data)
      |> assign(:memory_data, memory_data)
      |> assign(:memory_total, memory_total)
      |> assign(:network_in_data, network_in_data)
      |> assign(:network_out_data, network_out_data)
      |> assign(:disk_read_data, disk_read_data)
      |> assign(:disk_write_data, disk_write_data)

    legend_config = %{
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

    assigns = assign(assigns, :legend_config, legend_config)

    ~H"""
    <.card title={dgettext("dashboard", "Machine Metrics")} icon="chart_arcs" data-part="machine-metrics">
      <.card_section data-part="machine-metrics-charts">
        <div data-part="charts-grid" style="display: grid; grid-template-columns: repeat(2, 1fr); gap: var(--noora-spacing-9) var(--noora-spacing-7); padding: var(--noora-spacing-8);">
          <div>
            <span data-part="chart-title">CPU</span>
            <.chart
              id="cpu-usage-chart"
              type="line"
              style="height: 220px"
              labels={@labels}
              smooth={true}
              series={[
                %{name: "Usage", values: @cpu_data}
              ]}
              show_legend={false}
              extra_options={%{
                grid: %{left: "3%", right: "3%", bottom: "3%", top: "8%", containLabel: true},
                xAxis: %{boundaryGap: false, axisLabel: %{color: "var:noora-surface-label-secondary", interval: @label_interval}},
                yAxis: %{min: 0, max: 100, splitNumber: 4, splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}}, axisLabel: %{color: "var:noora-surface-label-secondary", formatter: "{value}%"}},
                tooltip: %{valueFormat: "{value}%"}
              }}
            />
          </div>
          <div>
            <span data-part="chart-title">Memory</span>
            <.chart
              id="memory-usage-chart"
              type="line"
              style="height: 220px"
              labels={@labels}
              smooth={true}
              series={[
                %{name: "Used", values: @memory_data}
              ]}
              show_legend={false}
              extra_options={%{
                grid: %{left: "3%", right: "3%", bottom: "3%", top: "8%", containLabel: true},
                xAxis: %{boundaryGap: false, axisLabel: %{color: "var:noora-surface-label-secondary", interval: @label_interval}},
                yAxis: %{min: 0, max: @memory_total, splitNumber: 4, splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}}, axisLabel: %{color: "var:noora-surface-label-secondary", formatter: "{value} GiB"}},
                tooltip: %{valueFormat: "{value} GiB"}
              }}
            />
          </div>
          <div>
            <span data-part="chart-title">Network</span>
            <.chart
              id="network-io-chart"
              type="line"
              style="height: 250px"
              labels={@labels}
              smooth={true}
              series={[
                %{name: "In", values: @network_in_data},
                %{name: "Out", values: @network_out_data}
              ]}
              colors={["var:noora-chart-primary", "var:noora-chart-secondary"]}
              extra_options={%{
                grid: %{left: "3%", right: "3%", bottom: "15%", top: "8%", containLabel: true},
                xAxis: %{boundaryGap: false, axisLabel: %{color: "var:noora-surface-label-secondary", interval: @label_interval}},
                yAxis: %{min: 0, splitNumber: 4, splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}}, axisLabel: %{color: "var:noora-surface-label-secondary", formatter: "{value} MiB/s"}},
                tooltip: %{valueFormat: "{value} MiB/s"},
                legend: @legend_config
              }}
            />
          </div>
          <div>
            <span data-part="chart-title">Disk I/O</span>
            <.chart
              id="disk-io-chart"
              type="line"
              style="height: 250px"
              labels={@labels}
              smooth={true}
              series={[
                %{name: "Read", values: @disk_read_data},
                %{name: "Write", values: @disk_write_data}
              ]}
              colors={["var:noora-chart-primary", "var:noora-chart-secondary"]}
              extra_options={%{
                grid: %{left: "3%", right: "3%", bottom: "15%", top: "8%", containLabel: true},
                xAxis: %{boundaryGap: false, axisLabel: %{color: "var:noora-surface-label-secondary", interval: @label_interval}},
                yAxis: %{min: 0, splitNumber: 4, splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}}, axisLabel: %{color: "var:noora-surface-label-secondary", formatter: "{value} MiB/s"}},
                tooltip: %{valueFormat: "{value} MiB/s"},
                legend: @legend_config
              }}
            />
          </div>
        </div>
      </.card_section>
    </.card>
    """
  end

  defp bytes_to_gib(bytes) do
    Float.round(bytes / (1024 * 1024 * 1024), 1)
  end

  defp bytes_to_mib(bytes) do
    Float.round(bytes / (1024 * 1024), 2)
  end

  defp format_time(offset_ms) do
    total_seconds = div(offset_ms, 1000)
    minutes = div(total_seconds, 60)
    seconds = rem(total_seconds, 60)
    "#{minutes}:#{String.pad_leading(Integer.to_string(seconds), 2, "0")}"
  end
end
