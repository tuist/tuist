defmodule TuistWeb.Components.MachineMetricsCharts do
  @moduledoc """
  Shared component for rendering machine metrics charts (CPU, Memory, Network I/O, Disk I/O).
  Used by both Xcode and Gradle build run pages.
  """
  use TuistWeb, :html
  use Noora

  def machine_metrics_charts(assigns) do
    metrics = assigns.metrics
    metrics =
      metrics
      |> Enum.group_by(fn m -> div(m.timestamp_offset_ms, 1000) end)
      |> Enum.sort_by(fn {k, _} -> k end)
      |> Enum.map(fn {_, samples} -> List.last(samples) end)

    labels = Enum.map(metrics, fn m -> format_time(m.timestamp_offset_ms) end)
    cpu_data = Enum.map(metrics, fn m -> Float.round(m.cpu_usage_percent / 1, 1) end)
    memory_data = Enum.map(metrics, fn m -> bytes_to_gb(m.memory_used_bytes) end)

    memory_total =
      case metrics do
        [first | _] -> bytes_to_gb(first.memory_total_bytes)
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

    ~H"""
    <.card title="Machine Metrics" icon="chart_arcs" data-part="machine-metrics">
      <.card_section data-part="machine-metrics-charts">
        <div data-part="charts-grid" style="display: grid; grid-template-columns: repeat(2, 1fr); gap: 16px; padding: 16px;">
          <div>
            <.chart
              id="cpu-usage-chart"
              type="line"
              style="height: 250px"
              labels={@labels}
              smooth={true}
              series={[
                %{name: "CPU Usage", values: @cpu_data}
              ]}
              extra_options={%{
                grid: %{width: "90%", left: "8%", height: "65%", top: "15%"},
                xAxis: %{boundaryGap: false, axisLabel: %{color: "var:noora-surface-label-secondary", interval: @label_interval}},
                yAxis: %{min: 0, max: 100, splitNumber: 4, splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}}, axisLabel: %{color: "var:noora-surface-label-secondary", formatter: "{value}%"}},
                tooltip: %{valueFormat: "{value}%"},
                title: %{text: "CPU Usage", textStyle: %{fontSize: 14, color: "var:noora-surface-label-primary"}}
              }}
            />
          </div>
          <div>
            <.chart
              id="memory-usage-chart"
              type="line"
              style="height: 250px"
              labels={@labels}
              smooth={true}
              series={[
                %{name: "Memory Used", values: @memory_data}
              ]}
              extra_options={%{
                grid: %{width: "90%", left: "8%", height: "65%", top: "15%"},
                xAxis: %{boundaryGap: false, axisLabel: %{color: "var:noora-surface-label-secondary", interval: @label_interval}},
                yAxis: %{min: 0, max: @memory_total, splitNumber: 4, splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}}, axisLabel: %{color: "var:noora-surface-label-secondary", formatter: "{value} GB"}},
                tooltip: %{valueFormat: "{value} GB"},
                title: %{text: "Memory Usage", textStyle: %{fontSize: 14, color: "var:noora-surface-label-primary"}}
              }}
            />
          </div>
          <div>
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
                grid: %{width: "90%", left: "8%", height: "60%", top: "15%"},
                xAxis: %{boundaryGap: false, axisLabel: %{color: "var:noora-surface-label-secondary", interval: @label_interval}},
                yAxis: %{min: 0, splitNumber: 4, splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}}, axisLabel: %{color: "var:noora-surface-label-secondary", formatter: "{value} MiB/s"}},
                tooltip: %{valueFormat: "{value} MiB/s"},
                title: %{text: "Network", textStyle: %{fontSize: 14, color: "var:noora-surface-label-primary"}},
                legend: %{left: "right", top: "top", textStyle: %{color: "var:noora-surface-label-secondary", fontSize: 10}}
              }}
            />
          </div>
          <div>
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
                grid: %{width: "90%", left: "8%", height: "60%", top: "15%"},
                xAxis: %{boundaryGap: false, axisLabel: %{color: "var:noora-surface-label-secondary", interval: @label_interval}},
                yAxis: %{min: 0, splitNumber: 4, splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}}, axisLabel: %{color: "var:noora-surface-label-secondary", formatter: "{value} MiB/s"}},
                tooltip: %{valueFormat: "{value} MiB/s"},
                title: %{text: "Disk I/O", textStyle: %{fontSize: 14, color: "var:noora-surface-label-primary"}},
                legend: %{left: "right", top: "top", textStyle: %{color: "var:noora-surface-label-secondary", fontSize: 10}}
              }}
            />
          </div>
        </div>
      </.card_section>
    </.card>
    """
  end

  defp bytes_to_gb(bytes) do
    Float.round(bytes / (1000 * 1000 * 1000), 1)
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
