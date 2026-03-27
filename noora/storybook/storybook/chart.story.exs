defmodule TuistWeb.Storybook.Chart do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &Noora.Chart.chart/1
  def layout, do: :one_column

  def variations do
    [
      %Variation{
        id: :multi_series_line,
        description: "Multi-series line chart with different dates",
        attributes: %{
          id: "multi-series-line",
          style: "width: 600px; height: 300px;",
          type: "line",
          show_legend: false,
          y_axis_min: 0,
          y_axis_max: 100,
          series: [
            %{
              name: "Binary cache effectiveness",
              type: "line",
              symbol: "none",
              data: [
                ["2024-08-24", 32],
                ["2024-09-15", 38],
                ["2024-10-03", 42],
                ["2024-10-20", 36],
                ["2024-11-08", 48],
                ["2024-11-27", 64],
                ["2024-12-15", 53]
              ]
            },
            %{
              name: "Selective test effectiveness",
              type: "line",
              symbol: "none",
              data: [
                ["2024-09-05", 48],
                ["2024-09-18", 52],
                ["2024-10-10", 45],
                ["2024-10-26", 38],
                ["2024-11-15", 42],
                ["2024-12-02", 56],
                ["2024-12-20", 62],
                ["2025-01-08", 58],
                ["2025-01-25", 64],
                ["2025-02-10", 60],
                ["2025-02-28", 66],
                ["2025-03-15", 70],
                ["2025-04-02", 65],
                ["2025-04-20", 72],
                ["2025-05-07", 68],
                ["2025-05-25", 74],
                ["2025-06-12", 78]
              ]
            }
          ],
          extra_options: %{
            yAxis: %{
              axisLabel: %{
                formatter: "{value}%"
              }
            },
            xAxis: %{
              type: "time",
              axisLabel: %{
                margin: 16,
                showMaxLabel: true,
                formatter: "fn:toLocaleDate"
              }
            },
            tooltip: %{
              valueFormat: "{value}%"
            }
          }
        }
      },
      %Variation{
        id: :horizontal_bar_comparison,
        description: "Horizontal bar comparison",
        attributes: %{
          id: "horizontal-bar-comparison",
          style: "width: 500px; height: 146px;",
          type: "bar",
          horizontal: true,
          labels: ["Selective Test", "Build Cache"],
          bar_radius: 7,
          bar_width: 24,
          series: [
            %{
              type: "bar",
              data: [19, 22],
              barGap: "-100%"
            },
            %{
              type: "bar",
              data: [7.2, 9]
            }
          ],
          extra_options: %{
            grid: %{
              height: 76,
              width: 400
            },
            xAxis: %{
              axisLabel: %{
                formatter: "{value}h",
                margin: 25
              },
              splitLine: %{
                lineStyle: %{
                  type: "dashed"
                }
              }
            },
            yAxis: %{
              boundaryGap: false,
              axisLine: %{
                show: false
              }
            }
          }
        }
      },
      %Variation{
        id: :test_run_duration,
        description: "Test run duration chart showing pass/fail status",
        attributes: %{
          id: "test-run-duration",
          style: "width: 700px; height: 300px;",
          type: "bar",
          y_axis_min: 0,
          grid_lines: true,
          show_legend: false,
          bar_radius: 2,
          bar_width: 8,
          series: [
            %{
              type: "bar",
              name: "Test Run",
              data: [
                # Pass runs (purple)
                %{value: 28, itemStyle: %{color: "var:noora-chart-primary"}},
                %{value: 23, itemStyle: %{color: "var:noora-chart-primary"}},
                %{value: 19, itemStyle: %{color: "var:noora-chart-primary"}},
                %{value: 25, itemStyle: %{color: "var:noora-chart-primary"}},
                # Fail runs (red)
                %{value: 37, itemStyle: %{color: "var:noora-chart-tertiary"}},
                %{value: 35, itemStyle: %{color: "var:noora-chart-tertiary"}},
                # Pass runs
                %{value: 22, itemStyle: %{color: "var:noora-chart-primary"}},
                %{value: 18, itemStyle: %{color: "var:noora-chart-primary"}},
                %{value: 16, itemStyle: %{color: "var:noora-chart-primary"}},
                %{value: 21, itemStyle: %{color: "var:noora-chart-primary"}},
                %{value: 24, itemStyle: %{color: "var:noora-chart-primary"}},
                %{value: 19, itemStyle: %{color: "var:noora-chart-primary"}},
                # Fail run
                %{value: 32, itemStyle: %{color: "var:noora-chart-tertiary"}},
                # Pass runs
                %{value: 20, itemStyle: %{color: "var:noora-chart-primary"}},
                %{value: 17, itemStyle: %{color: "var:noora-chart-primary"}},
                %{value: 21, itemStyle: %{color: "var:noora-chart-primary"}},
                %{value: 25, itemStyle: %{color: "var:noora-chart-primary"}},
                %{value: 23, itemStyle: %{color: "var:noora-chart-primary"}},
                %{value: 18, itemStyle: %{color: "var:noora-chart-primary"}},
                %{value: 15, itemStyle: %{color: "var:noora-chart-primary"}},
                %{value: 22, itemStyle: %{color: "var:noora-chart-primary"}},
                # Fail run
                %{value: 30, itemStyle: %{color: "var:noora-chart-tertiary"}},
                # Pass runs
                %{value: 20, itemStyle: %{color: "var:noora-chart-primary"}},
                %{value: 19, itemStyle: %{color: "var:noora-chart-primary"}},
                %{value: 24, itemStyle: %{color: "var:noora-chart-primary"}},
                %{value: 27, itemStyle: %{color: "var:noora-chart-primary"}},
                %{value: 23, itemStyle: %{color: "var:noora-chart-primary"}},
                %{value: 20, itemStyle: %{color: "var:noora-chart-primary"}},
                %{value: 18, itemStyle: %{color: "var:noora-chart-primary"}},
                %{value: 22, itemStyle: %{color: "var:noora-chart-primary"}}
              ]
            }
          ],
          extra_options: %{
            tooltip: %{
              show: false
            },
            xAxis: %{
              axisLabel: %{
                show: false
              }
            },
            yAxis: %{
              axisLabel: %{
                formatter: "fn:formatSeconds"
              }
            }
          }
        }
      }
    ]
  end
end
