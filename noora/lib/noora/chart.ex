defmodule Noora.Chart do
  @moduledoc """
  A powerful charting component powered by ECharts.

  ## Example

  ```elixir
  <.chart
    id="revenue-chart"
    type="line"
    series={[10, 20, 30, 40]}
    labels={["Q1", "Q2", "Q3", "Q4"]}
    title="Quarterly Revenue"
  />
  ```

  ## Custom formatters

  For labels, we offer several built-in formatters:

  - `formatSeconds`: Formats seconds into human readable time (e.g., "30s", "2m 30s", "1h 5m")
  - `formatMilliseconds`: Formats milliseconds into human readable time
  - `formatHours`: Formats hours into human readable time (e.g., "30m", "2h 30m", "1d 5h")
  - `formatBytes`: Formats bytes into human readable size (e.g., "1.5 KB", "2 MB", "1 GB")
  - `toLocaleDate`: Formats dates into locale-specific format
  - `firstAndLastDate`: Renders the first and last label only as dates. This is useful for time series charts.

  If this does not match your use case, you can also pass a completely custom formatter. This expects a global `nooraChartFormatters` object
  with a function named after the formatter you want to use. For example, if you want to use a "first label only" formatter, you can define
  a function named `firstLabelOnly` in the `nooraChartFormatters` object as such:

  ```js
  nooraChartFormatters = {
    firstLabelOnly: (el) => (value, index) => {
      if (index === 0) {
        return value;
      }
    }
  };
  ```

  You can use these function-based formatters in your chart configuration as such:

  ```elixir
  %{
    extra_options: %{
      xAxis: %{
        axisLabel: %{
          formatter: "fn:firstLabelOnly"
        }
      }
    }
  ```
  """
  use Phoenix.Component

  attr(:id, :string, required: true, doc: "The ID used for the chart container")

  attr(:type, :string,
    default: "bar",
    values: ["bar", "line", "pie", "scatter", "radar"],
    doc: """
    The type of chart to render. Defaults to "bar".
    Available types: bar, line, pie, scatter, radar
    """
  )

  attr(:series, :any,
    default: nil,
    doc: """
    The series data for the chart. Structure depends on chart type:

    For bar/line charts:
      - A list of values: [10, 20, 30]
      - A list of maps with names: [%{name: "Series 1", values: [10, 20, 30]}]
      - A list of series with different types: [%{name: "Bar", type: "bar", values: [10, 20, 30]}, %{name: "Line", type: "line", values: [5, 15, 25]}]
      - A list of time series: [%{name: "Series 1", data: [["2024-01-01", 10], ["2024-01-02", 20]]}]

    For pie charts:
      - A list of maps with name and value: [%{name: "A", value: 10}, %{name: "B", value: 20}]

    For scatter charts:
      - A list of [x, y] points: [[10, 20], [30, 40]]
      - A list of maps with series: [%{name: "Series 1", data: [[10, 20], [30, 40]]}]
    """
  )

  attr(:labels, :list,
    default: [],
    doc: """
    Category labels for the x-axis (for bar/line charts) or data point names (for pie charts).
    Example: ["Jan", "Feb", "Mar"]
    """
  )

  attr(:title, :string,
    default: nil,
    doc: """
    Main title for the chart.
    """
  )

  attr(:subtitle, :string,
    default: nil,
    doc: """
    Subtitle shown below the main title.
    """
  )

  attr(:show_legend, :boolean,
    default: true,
    doc: """
    Whether to show the chart legend.
    """
  )

  attr(:legend_position, :string,
    default: "top",
    values: ["top", "bottom", "left", "right"],
    doc: """
    Position of the legend. Options: "top", "bottom", "left", "right"
    """
  )

  attr(:colors, :list,
    default: [
      "var:noora-chart-primary",
      "var:noora-chart-secondary",
      "var:noora-chart-tertiary",
      "var:noora-chart-quaternary"
    ],
    doc: """
    Custom colors for data series.

    The given items can either be a hex string, such as "#4C9AFF", or a CSS variable, prefixed with `var:`, but omitting the `--` prefix,
    such as `chart-primary`.
    The CSS variable is expected to be on the `:root` element, so the variable would be defined as such:

    ```css
    :root {
      --chart-primary: #4C9AFF;
    }
    ```

    In addition, the color setting supports the `light-dark()` function, which can be used to automatically resolve the appropriate color
    based on the the color scheme. That way, the variable can be defined as such:

    ```css
    :root {
      --chart-primary: light-dark(#4C9AFF, #36B37E);
    }
    ```

    Example: ["#4C9AFF", "#36B37E", "#FF5630", "#FFAB00", "#6554C0"]
    """
  )

  attr(:stacked, :boolean,
    default: false,
    doc: """
    For bar/line charts, whether series should be stacked.
    """
  )

  attr(:show_values, :boolean,
    default: false,
    doc: """
    Whether to show data values directly on the chart.
    """
  )

  attr(:smooth, :boolean,
    default: false,
    doc: """
    For line charts, whether to use smooth curves instead of straight lines.
    """
  )

  attr(:donut, :boolean,
    default: false,
    doc: """
    For pie charts, whether to render as a donut chart.
    """
  )

  attr(:donut_radius, :list,
    default: ["50%", "70%"],
    doc: """
    For donut charts, the inner and outer radius. Default: ["50%", "70%"]
    """
  )

  attr(:x_axis_name, :string,
    default: nil,
    doc: """
    Name for the X axis. Example: "Month"
    """
  )

  attr(:y_axis_name, :string,
    default: nil,
    doc: """
    Name for the Y axis. Example: "Revenue ($)"
    """
  )

  attr(:x_axis_min, :integer,
    default: nil,
    doc: """
    Minimum value for the X axis. Example: 0
    """
  )

  attr(:x_axis_max, :integer,
    default: nil,
    doc: """
    Maximum value for the X axis. Example: 100
    """
  )

  attr(:y_axis_min, :integer,
    default: nil,
    doc: """
    Minimum value for the Y axis. Example: 0
    """
  )

  attr(:y_axis_max, :integer,
    default: nil,
    doc: """
    Maximum value for the Y axis. Example: 100
    """
  )

  attr(:grid_lines, :boolean,
    default: true,
    doc: """
    Whether to show grid lines on the chart.
    """
  )

  attr(:horizontal, :boolean,
    default: false,
    doc: """
    Whether to display a horizontal bar chart (with category axis on y-axis).
    """
  )

  attr(:bar_width, :integer,
    default: nil,
    doc: """
    Width of bars in bar charts (in pixels).
    """
  )

  attr(:bar_radius, :integer,
    default: nil,
    doc: """
    Border radius of bars in bar charts (in pixels).
    """
  )

  attr(:extra_options, :map,
    default: %{},
    doc: """
    Additional ECharts options for advanced customization.
    These will be deeply merged with options generated from other attributes.
    """
  )

  attr(:rest, :global, doc: "Additional HTML attributes to add to the container div")

  def chart(assigns) do
    # Load chart type specific defaults and build the complete chart options
    type_defaults = get_type_defaults(assigns.type)
    chart_options = build_options(assigns, type_defaults)
    assigns = assign(assigns, option: chart_options)

    ~H"""
    <div id={@id} class="noora-chart" phx-hook="NooraChart" {@rest}>
      {# The actual chart is managed by ECharts, so we are ignoring any updates by LiveView. The chart should be updated by changing the component attributes. #}
      <div id={"#{@id}-chart"} data-part="chart" phx-update="ignore"></div>
      <div data-part="data" hidden>{Jason.encode!(@option)}</div>
    </div>
    """
  end

  # Main function to build all chart options by combining defaults with user-provided configuration
  defp build_options(assigns, type_defaults) do
    # Start with default options and merge with chart type-specific defaults
    base_options = DeepMerge.deep_merge(default(), type_defaults)

    # Extract specific attributes to avoid passing full assigns map to helper functions
    title = assigns.title
    subtitle = assigns.subtitle
    chart_type = assigns.type
    show_legend = assigns.show_legend
    legend_position = assigns.legend_position
    colors = assigns.colors
    grid_lines = assigns.grid_lines
    horizontal = assigns.horizontal
    labels = assigns.labels

    # Axis configuration
    axis_config = %{
      x_axis_name: assigns.x_axis_name,
      y_axis_name: assigns.y_axis_name,
      x_axis_min: assigns.x_axis_min,
      x_axis_max: assigns.x_axis_max,
      y_axis_min: assigns.y_axis_min,
      y_axis_max: assigns.y_axis_max,
      extra_options: assigns.extra_options,
      horizontal: horizontal,
      labels: labels
    }

    # Series configuration
    series_config = %{
      stacked: assigns.stacked,
      show_values: assigns.show_values,
      smooth: assigns.smooth,
      donut: assigns.donut,
      donut_radius: assigns.donut_radius,
      bar_width: assigns.bar_width,
      bar_radius: assigns.bar_radius,
      horizontal: horizontal
    }

    # Build options by adding each component
    custom_options =
      %{}
      |> add_title_options(title, subtitle)
      |> add_legend_options(show_legend, legend_position)
      |> add_tooltip_options(chart_type)
      |> add_colors(colors)
      |> add_grid_options(grid_lines)
      |> add_axis_options(chart_type, axis_config)
      |> add_series_options(chart_type, assigns.series, labels, series_config)

    # Merge the base options with custom options and extra options
    merged_options =
      base_options
      |> DeepMerge.deep_merge(custom_options)
      |> DeepMerge.deep_merge(Map.delete(assigns.extra_options, :series))

    # Apply bar radius to all bar series if it's set
    merged_options =
      if chart_type == "bar" && assigns.bar_radius do
        apply_bar_radius_to_series(merged_options, assigns.bar_radius)
      else
        merged_options
      end

    merged_options
  end

  # Adds chart title and subtitle if provided
  defp add_title_options(options, title, subtitle) do
    title_opts =
      %{}
      |> maybe_add_to_map(:text, title)
      |> maybe_add_to_map(:subtext, subtitle)

    if map_size(title_opts) > 0 do
      Map.put(options, :title, title_opts)
    else
      options
    end
  end

  # Configures the legend display and position
  defp add_legend_options(options, show_legend, legend_position) do
    if show_legend do
      legend_position =
        case legend_position do
          "top" -> %{top: "0", left: "center"}
          "bottom" -> %{bottom: "0", left: "center"}
          "left" -> %{left: "0", top: "center", orient: "vertical"}
          "right" -> %{right: "0", top: "center", orient: "vertical"}
          _ -> %{top: "0", left: "center"}
        end

      Map.put(options, :legend, legend_position)
    else
      Map.put(options, :legend, %{show: false})
    end
  end

  # Sets tooltip trigger based on chart type (item for pie, axis for others)
  defp add_tooltip_options(options, chart_type) do
    trigger_value = if chart_type == "pie", do: "item", else: "axis"

    tooltip = %{
      trigger: trigger_value
    }

    Map.put(options, :tooltip, tooltip)
  end

  # Adds custom color configuration if provided
  defp add_colors(options, colors) do
    if length(colors) > 0 do
      Map.put(options, :colors, colors)
    else
      options
    end
  end

  # Configures grid display
  defp add_grid_options(options, grid_lines) do
    grid = Map.get(options, :grid, %{})

    grid =
      if grid_lines do
        grid
      else
        Map.put(grid, :show, false)
      end

    Map.put(options, :grid, grid)
  end

  # Handles axis configuration based on chart type
  defp add_axis_options(options, chart_type, axis_config) do
    # Skip axis configuration for pie and radar charts
    if chart_type in ["pie", "radar"] do
      options
    else
      x_axis = build_axis_options(:x, axis_config)
      y_axis = build_axis_options(:y, axis_config)

      # Handle horizontal bar charts by swapping axis types
      {x_axis, y_axis} =
        if axis_config.horizontal && chart_type == "bar" do
          # For horizontal bars, x is value axis, y is category axis
          x_axis = Map.put_new(x_axis, :type, "value")
          y_axis = Map.put_new(y_axis, :type, "category")

          # Add labels to y-axis for horizontal charts
          # credo:disable-for-next-line
          if length(axis_config.labels) > 0 do
            y_axis = Map.put(y_axis, :data, axis_config.labels)
            x_axis = Map.delete(x_axis, :data)
            {x_axis, y_axis}
          else
            {x_axis, y_axis}
          end
        else
          # Default orientation: x is category, y is value
          x_axis = Map.put_new(x_axis, :type, "category")
          y_axis = Map.put_new(y_axis, :type, "value")
          {x_axis, y_axis}
        end

      options
      |> Map.put(:xAxis, x_axis)
      |> Map.put(:yAxis, y_axis)
    end
  end

  # Builds the axis configuration for either x or y axis
  # credo:disable-for-next-line
  defp build_axis_options(axis_type, config) do
    axis_key = if axis_type == :x, do: :xAxis, else: :yAxis
    # Start with any user-provided axis config from extra_options
    base_axis = Map.get(config.extra_options, axis_key, %{})

    # Add axis name if provided
    axis_name = if axis_type == :x, do: config.x_axis_name, else: config.y_axis_name
    base_axis = if axis_name, do: Map.put(base_axis, :name, axis_name), else: base_axis

    # Add min/max values if provided
    min_value = if axis_type == :x, do: config.x_axis_min, else: config.y_axis_min
    max_value = if axis_type == :x, do: config.x_axis_max, else: config.y_axis_max

    base_axis = if min_value, do: Map.put(base_axis, :min, min_value), else: base_axis
    base_axis = if max_value, do: Map.put(base_axis, :max, max_value), else: base_axis

    # Add labels as data for the x-axis (when not horizontal)
    if axis_type == :x && length(config.labels) > 0 && !config.horizontal do
      Map.put(base_axis, :data, config.labels)
    else
      base_axis
    end
  end

  # Configures series data based on chart type and provided data
  defp add_series_options(options, _chart_type, nil, _labels, _config) do
    # No series data provided
    options
  end

  defp add_series_options(options, chart_type, series, labels, config) do
    processed_series = process_data_for_chart_type(chart_type, series, labels, config)
    Map.put(options, :series, processed_series)
  end

  # Process data for different chart types
  defp process_data_for_chart_type(type, series, labels, opts) when type in ["bar", "line"] do
    process_bar_line_data(type, series, labels, opts)
  end

  # Pie chart configuration
  defp process_data_for_chart_type("pie", series, _labels, opts) do
    [
      %{
        type: "pie",
        radius: if(opts.donut, do: opts.donut_radius, else: "60%"),
        data: normalize_pie_data(series),
        label: %{
          show: opts.show_values
        }
      }
    ]
  end

  # Scatter chart configuration
  defp process_data_for_chart_type("scatter", series, _labels, opts) do
    normalize_scatter_data(series, opts)
  end

  # Radar chart configuration
  defp process_data_for_chart_type("radar", series, _labels, _opts) do
    [%{type: "radar", data: normalize_radar_data(series)}]
  end

  # Default fallback for other chart types
  defp process_data_for_chart_type(_type, series, _labels, _opts) do
    # Default fallback - pass through the data for advanced usage
    series
  end

  # Processes data for bar and line charts, handling different input formats
  # credo:disable-for-next-line
  defp process_bar_line_data(type, series, _labels, opts) do
    cond do
      # Simple array of numbers: [10, 20, 30]
      is_list(series) && series |> List.first() |> is_number() ->
        [
          build_series_config(%{
            type: type,
            data: series,
            opts: opts
          })
        ]

      # Array of series objects: [%{name: "Series 1", values: [10, 20, 30]}]
      is_list(series) && series |> List.first() |> is_map() ->
        Enum.map(series, fn series_item ->
          # Support both 'values' and 'data' keys for consistency
          values = series_item[:values] || series_item[:data] || []

          # Extract known properties we handle
          known_props = [:type, :name, :values, :data, :show_values, :smooth]

          # Get all additional series options that should be passed through
          additional_options = Map.drop(series_item, known_props)

          build_series_config(%{
            # Allow mixed chart types (bar/line)
            type: series_item[:type] || type,
            name: series_item[:name] || "",
            data: values,
            # Override global setting per series
            show_values: series_item[:show_values],
            # Override global setting per series
            smooth: series_item[:smooth],
            additional_options: additional_options,
            opts: opts
          })
        end)

      # Fallback for any other data format
      true ->
        [
          build_series_config(%{
            type: type,
            data: series,
            opts: opts
          })
        ]
    end
  end

  # Creates configuration for a single chart series
  defp build_series_config(%{type: type, data: data, opts: opts} = config) do
    # Base series configuration
    series = %{
      type: type,
      data: data,
      stack: if(opts.stacked, do: "total"),
      label: %{
        show: config[:show_values] || opts.show_values
      }
    }

    # Add line chart specific options
    series =
      if type == "line" do
        series
        |> Map.put(:smooth, config[:smooth] || opts.smooth)
        # Remove data point dots
        |> Map.put(:symbol, "none")
      else
        series
      end

    # Add bar chart specific options
    series =
      if type == "bar" do
        series
        |> maybe_add_to_map(:barWidth, opts.bar_width)
        |> maybe_add_item_style(opts.bar_radius)
      else
        series
      end

    # Add series name if provided
    series = if config[:name], do: Map.put(series, :name, config[:name]), else: series

    # Merge any additional options passed directly from the series item
    if config[:additional_options] && map_size(config[:additional_options]) > 0 do
      Map.merge(series, config[:additional_options])
    else
      series
    end
  end

  # Helper to add item style with border radius to bar charts
  defp maybe_add_item_style(series, nil), do: series

  defp maybe_add_item_style(series, bar_radius) do
    item_style = Map.get(series, :itemStyle, %{})
    item_style = Map.put(item_style, :borderRadius, bar_radius)
    Map.put(series, :itemStyle, item_style)
  end

  # Apply border radius to all bar series in a chart
  defp apply_bar_radius_to_series(options, bar_radius) do
    case Map.get(options, :series) do
      nil ->
        options

      series when is_list(series) ->
        updated_series =
          Enum.map(series, fn series_item ->
            # credo:disable-for-next-line
            if series_item[:type] == "bar" do
              item_style = Map.get(series_item, :itemStyle, %{})
              item_style = Map.put(item_style, :borderRadius, bar_radius)
              Map.put(series_item, :itemStyle, item_style)
            else
              series_item
            end
          end)

        Map.put(options, :series, updated_series)

      _ ->
        options
    end
  end

  # Normalizes pie chart data to expected format
  # credo:disable-for-next-line
  defp normalize_pie_data(series) when is_list(series) do
    cond do
      # Series already in correct format: [%{name: "A", value: 10}]
      series |> List.first() |> is_map() && Map.has_key?(List.first(series), :value) ->
        series

      # Series in different format: [%{name: "A", count: 10}]
      series |> List.first() |> is_map() ->
        Enum.map(series, fn item ->
          %{
            name: item[:name] || item[:label] || "",
            value: item[:value] || item[:count] || 0
          }
        end)

      # Just values without names: [10, 20, 30]
      series |> List.first() |> is_number() ->
        Enum.with_index(series, fn value, index ->
          %{name: "Item #{index + 1}", value: value}
        end)

      # Fallback for any other format
      true ->
        series
    end
  end

  # Normalizes scatter chart data to expected format
  defp normalize_scatter_data(series, _opts) when is_list(series) do
    cond do
      # Multiple series: [%{name: "Series 1", data: [[10, 20], [30, 40]]}]
      series |> List.first() |> is_map() &&
          (Map.has_key?(List.first(series), :data) || Map.has_key?(List.first(series), :values)) ->
        Enum.map(series, fn series_item ->
          values = series_item[:data] || series_item[:values] || []

          %{
            type: "scatter",
            name: series_item[:name] || "",
            data: values
          }
        end)

      # Direct array of points: [[10, 20], [30, 40]]
      series |> List.first() |> is_list() ->
        [
          %{
            type: "scatter",
            data: series
          }
        ]

      # Fallback for any other format
      true ->
        [%{type: "scatter", data: series}]
    end
  end

  # Normalizes radar chart data to expected format
  defp normalize_radar_data(series) when is_list(series) do
    if series |> List.first() |> is_map() do
      series
    else
      [%{value: series, name: "Series"}]
    end
  end

  # Utility to conditionally add a key-value pair to a map
  defp maybe_add_to_map(map, _key, nil), do: map
  defp maybe_add_to_map(map, _key, ""), do: map
  defp maybe_add_to_map(map, key, value), do: Map.put(map, key, value)

  # Default base configuration for all charts
  defp default do
    %{
      grid: %{
        containLabel: true
      },
      tooltip: %{
        show: true
      },
      xAxis: %{
        axisLabel: %{fontSize: 10},
        splitLine: %{
          lineStyle: %{
            type: "dashed"
          }
        },
        # Hide axis line and ticks by default
        axisLine: %{show: false},
        axisTick: %{show: false}
      },
      yAxis: %{
        axisLabel: %{fontSize: 10},
        splitLine: %{
          lineStyle: %{
            type: "dashed"
          }
        },
        # Hide axis line and ticks by default
        axisLine: %{show: false},
        axisTick: %{show: false}
      },
      textStyle: %{
        fontFamily: "Geist Mono"
      }
    }
  end

  # Chart type specific default configurations
  defp get_type_defaults("scatter") do
    %{
      xAxis: %{
        axisLabel: %{fontSize: 10},
        # Scale axes to data range rather than starting at zero
        scale: true
      },
      yAxis: %{
        axisLabel: %{fontSize: 10},
        scale: true
      }
    }
  end

  defp get_type_defaults("radar") do
    %{
      radar: %{
        shape: "circle",
        # Will be populated with data categories
        indicator: []
      }
    }
  end

  defp get_type_defaults(_) do
    %{}
  end
end
