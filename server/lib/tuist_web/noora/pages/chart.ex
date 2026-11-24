defmodule TuistWeb.Noora.Pages.Chart do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Chart",
    description: "Plots metrics such as build durations, cache hit rates, and test runs with Apache ECharts.",
    components: [{Noora.Chart, :chart}],
    guidelines: [
      "Give every chart an `id` that is unique on the page and a height on the container, for example through `style`. The chart fills its container and has no height of its own.",
      "Pass category names in `labels` and values in `series`, either as a list of numbers or as maps with a `name` and `values`. Time series take `data` as `[date, value]` pairs.",
      "Format axes and tooltips with the built-in formatters by name, such as `fn:formatSeconds`, `fn:formatMilliseconds`, `fn:formatBytes`, and `fn:toLocaleDate`, in `extra_options`.",
      "Use `extra_options` for any ECharts option the attributes do not cover. It is deep-merged over the generated options.",
      "Keep the default `colors` or pass `var:` tokens, which follow the light and dark theme. Hex values stay the same in both.",
      "Hide the legend with `show_legend={false}` when a chart has a single series. Add `data-lazy=\"true\"` to defer charts that start offscreen."
    ]

  example "Line",
    description: "A single series over time. The tooltip and axis share the same formatter.",
    layout: :column do
    ~H"""
    <.chart
      id="chart-line-build-duration"
      type="line"
      style="height: 280px;"
      labels={["Oct 14", "Oct 15", "Oct 16", "Oct 17", "Oct 18", "Oct 19", "Oct 20"]}
      series={[%{name: "Average build duration", values: [184, 172, 196, 158, 149, 163, 141]}]}
      show_legend={false}
      y_axis_min={0}
      extra_options={
        %{
          yAxis: %{axisLabel: %{formatter: "fn:formatSeconds"}},
          tooltip: %{valueFormat: "fn:formatSeconds"}
        }
      }
    />
    """
  end

  example "Multiple series",
    description: "Each map in `series` becomes a line with its own legend entry.",
    layout: :column do
    ~H"""
    <.chart
      id="chart-multiple-series-percentiles"
      type="line"
      style="height: 280px;"
      smooth={0.1}
      legend_position="bottom"
      labels={["Oct 14", "Oct 15", "Oct 16", "Oct 17", "Oct 18", "Oct 19", "Oct 20"]}
      series={[
        %{name: "p50", values: [142, 138, 151, 129, 124, 133, 118]},
        %{name: "p90", values: [312, 296, 341, 287, 270, 302, 264]}
      ]}
      y_axis_min={0}
      extra_options={
        %{
          yAxis: %{axisLabel: %{formatter: "fn:formatSeconds"}},
          tooltip: %{valueFormat: "fn:formatSeconds"}
        }
      }
    />
    """
  end

  example "Stacked bars",
    description: "With `stacked`, the series of each category add up to one bar.",
    layout: :column do
    ~H"""
    <.chart
      id="chart-stacked-bars-cache-hits"
      type="bar"
      style="height: 280px;"
      stacked
      bar_width={16}
      legend_position="bottom"
      labels={["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]}
      series={[
        %{name: "Local hits", values: [412, 389, 455, 431, 398, 64, 52]},
        %{name: "Remote hits", values: [268, 301, 284, 322, 296, 41, 37]},
        %{name: "Misses", values: [94, 112, 87, 103, 91, 18, 15]}
      ]}
    />
    """
  end

  example "Horizontal bars", description: "With `horizontal`, the labels move to the y-axis.", layout: :column do
    ~H"""
    <.chart
      id="chart-horizontal-bars-time-saved"
      type="bar"
      style="height: 160px;"
      horizontal
      show_legend={false}
      bar_width={20}
      bar_radius={4}
      labels={["Selective testing", "Binary cache"]}
      series={[%{name: "Time saved", values: [19, 22]}]}
      extra_options={
        %{
          xAxis: %{axisLabel: %{formatter: "fn:formatHours"}},
          tooltip: %{valueFormat: "fn:formatHours"}
        }
      }
    />
    """
  end

  example "Donut",
    description: "Pie charts take maps with a `name` and a `value`. `donut` cuts out the center.",
    layout: :column do
    ~H"""
    <.chart
      id="chart-donut-cache-outcomes"
      type="pie"
      style="height: 260px;"
      donut
      legend_position="right"
      series={[
        %{name: "Local hits", value: 2_541},
        %{name: "Remote hits", value: 1_549},
        %{name: "Misses", value: 520}
      ]}
    />
    """
  end

  example "Range bars",
    description:
      "A `custom` chart with the built-in range-bar renderer draws work on lanes, with start and end in milliseconds.",
    layout: :column do
    ~H"""
    <.chart
      id="chart-range-bars-build-timeline"
      type="custom"
      style="height: 220px;"
      show_legend={false}
      labels={["Analysis", "Lane 1", "Lane 2"]}
      series={[
        %{
          type: "custom",
          renderItem: "fn:rangeBar",
          data: [
            %{
              value: [0, 0, 980],
              name: "Analyze dependencies",
              durationLabel: "Duration",
              startLabel: "Started after"
            },
            %{
              value: [1, 820, 2_270],
              name: "Compile sources",
              durationLabel: "Duration",
              startLabel: "Started after"
            },
            %{
              value: [2, 1_150, 1_930],
              name: "Link TuistKit",
              durationLabel: "Duration",
              startLabel: "Started after"
            }
          ]
        }
      ]}
      extra_options={
        %{
          grid: %{left: 96, right: 24, top: 16, bottom: 32},
          tooltip: %{formatter: "fn:rangeBarTooltip"},
          xAxis: %{axisLabel: %{formatter: "fn:formatMilliseconds"}}
        }
      }
    />
    """
  end
end
