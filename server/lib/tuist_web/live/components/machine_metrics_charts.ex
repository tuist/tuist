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
      |> Enum.group_by(fn m -> trunc(m.timestamp) end)
      |> Enum.sort_by(fn {k, _} -> k end)
      |> Enum.map(fn {_, samples} -> List.last(samples) end)

    labels = Enum.map(metrics, fn m -> format_iso_time(m.timestamp) end)
    cpu_data = Enum.map(metrics, fn m -> Float.round(m.cpu_usage_percent + 0.0, 1) end)
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

    label_custom_values =
      case labels do
        [] -> []
        [single] -> [single]
        list -> [hd(list), List.last(list)]
      end

    legend_config = %{
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
    }

    assigns =
      assigns
      |> assign(:labels, labels)
      |> assign(:label_custom_values, label_custom_values)
      |> assign(:cpu_data, cpu_data)
      |> assign(:memory_data, memory_data)
      |> assign(:memory_total, memory_total)
      |> assign(:network_in_data, network_in_data)
      |> assign(:network_out_data, network_out_data)
      |> assign(:disk_read_data, disk_read_data)
      |> assign(:disk_write_data, disk_write_data)
      |> assign(:legend_config, legend_config)

    ~H"""
    <div class="tuist-machine-metrics">
      <.card icon="chart_dots" title={dgettext("dashboard", "Metrics")}>
        <.card_section data-part="charts-grid">
          <.card_section data-part="chart-card">
            <span data-part="chart-title">CPU</span>
            <.chart
              id="cpu-usage-chart"
              type="line"
              labels={@labels}
              smooth={0.1}
              series={[%{name: "Usage", values: @cpu_data}]}
              show_legend={false}
              extra_options={
                %{
                  grid: %{left: "3%", right: "5%", bottom: "10%", top: "8%", containLabel: true},
                  xAxis: %{
                    boundaryGap: false,
                    axisLabel: %{
                      color: "var:noora-surface-label-secondary",
                      customValues: @label_custom_values,
                      padding: [10, 0, 0, 0],
                      formatter: "fn:toLocaleTime"
                    }
                  },
                  yAxis: %{
                    min: 0,
                    max: 100,
                    splitNumber: 4,
                    splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}},
                    axisLabel: %{color: "var:noora-surface-label-secondary", formatter: "{value}%"}
                  },
                  tooltip: %{valueFormat: "{value}%", dateFormat: "minute"}
                }
              }
            />
          </.card_section>
          <.card_section data-part="chart-card">
            <span data-part="chart-title">Memory</span>
            <.chart
              id="memory-usage-chart"
              type="line"
              labels={@labels}
              smooth={0.1}
              series={[%{name: "Used", values: @memory_data}]}
              show_legend={false}
              extra_options={
                %{
                  grid: %{left: "3%", right: "5%", bottom: "10%", top: "8%", containLabel: true},
                  xAxis: %{
                    boundaryGap: false,
                    axisLabel: %{
                      color: "var:noora-surface-label-secondary",
                      customValues: @label_custom_values,
                      padding: [10, 0, 0, 0],
                      formatter: "fn:toLocaleTime"
                    }
                  },
                  yAxis: %{
                    min: 0,
                    max: @memory_total,
                    splitNumber: 4,
                    splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}},
                    axisLabel: %{
                      color: "var:noora-surface-label-secondary",
                      formatter: "{value} GB"
                    }
                  },
                  tooltip: %{valueFormat: "{value} GB", dateFormat: "minute"}
                }
              }
            />
          </.card_section>
          <.card_section data-part="chart-card">
            <span data-part="chart-title">Network</span>
            <.chart
              id="network-io-chart"
              type="line"
              labels={@labels}
              smooth={0.1}
              series={[
                %{name: "In", values: @network_in_data},
                %{name: "Out", values: @network_out_data}
              ]}
              colors={["var:noora-chart-primary", "var:noora-chart-secondary"]}
              extra_options={
                %{
                  grid: %{left: "3%", right: "5%", bottom: "25%", top: "8%", containLabel: true},
                  xAxis: %{
                    boundaryGap: false,
                    axisLabel: %{
                      color: "var:noora-surface-label-secondary",
                      customValues: @label_custom_values,
                      padding: [10, 0, 0, 0],
                      formatter: "fn:toLocaleTime"
                    }
                  },
                  yAxis: %{
                    min: 0,
                    splitNumber: 4,
                    splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}},
                    axisLabel: %{
                      color: "var:noora-surface-label-secondary",
                      formatter: "{value} MiB/s"
                    }
                  },
                  tooltip: %{valueFormat: "{value} MiB/s", dateFormat: "minute"},
                  legend: @legend_config
                }
              }
            />
          </.card_section>
          <.card_section data-part="chart-card">
            <span data-part="chart-title">Disk I/O</span>
            <.chart
              id="disk-io-chart"
              type="line"
              labels={@labels}
              smooth={0.1}
              series={[
                %{name: "Read", values: @disk_read_data},
                %{name: "Write", values: @disk_write_data}
              ]}
              colors={["var:noora-chart-primary", "var:noora-chart-secondary"]}
              extra_options={
                %{
                  grid: %{left: "3%", right: "5%", bottom: "25%", top: "8%", containLabel: true},
                  xAxis: %{
                    boundaryGap: false,
                    axisLabel: %{
                      color: "var:noora-surface-label-secondary",
                      customValues: @label_custom_values,
                      padding: [10, 0, 0, 0],
                      formatter: "fn:toLocaleTime"
                    }
                  },
                  yAxis: %{
                    min: 0,
                    splitNumber: 4,
                    splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}},
                    axisLabel: %{
                      color: "var:noora-surface-label-secondary",
                      formatter: "{value} MiB/s"
                    }
                  },
                  tooltip: %{valueFormat: "{value} MiB/s", dateFormat: "minute"},
                  legend: @legend_config
                }
              }
            />
          </.card_section>
        </.card_section>
      </.card>
    </div>
    """
  end

  defp bytes_to_gb(bytes) do
    Float.round(bytes / (1000 * 1000 * 1000), 1)
  end

  defp bytes_to_mib(bytes) do
    Float.round(bytes / (1024 * 1024), 2)
  end

  defp format_iso_time(epoch_seconds) do
    seconds = trunc(epoch_seconds)
    seconds |> DateTime.from_unix!() |> DateTime.to_iso8601()
  end
end
