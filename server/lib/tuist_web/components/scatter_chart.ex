defmodule TuistWeb.Components.ScatterChart do
  @moduledoc false
  use Phoenix.Component
  use Noora

  attr(:id, :string, required: true, doc: "DOM id for the chart element.")

  attr(:chart, :any,
    required: true,
    doc: "AsyncResult whose result is :line or {:scatter, %{series, truncated, oldest_entry}}."
  )

  attr(:period, :any, required: true, doc: "{start_datetime, end_datetime} tuple for the x-axis range.")

  attr(:value_format, :string,
    required: true,
    doc: ~s|y-axis/tooltip value format (e.g. "{value}%" or "fn:formatSeconds").|
  )

  attr(:y_axis_max, :integer, default: nil, doc: "Optional y-axis upper bound. Use 100 for percentage charts.")
  attr(:narrow_grid, :boolean, default: false, doc: "Use narrower grid (93%/7%) instead of the default full-width grid.")
  attr(:url_fn, :any, default: nil, doc: "Optional function (point -> url) to make scatter dots clickable.")

  attr(:truncation_title, :string,
    required: true,
    doc: "Localized alert title shown when the scatter result is truncated."
  )

  def scatter_chart(assigns) do
    ~H"""
    <.chart
      :if={scatter?(@chart)}
      id={@id}
      type="scatter"
      extra_options={extra_options(@period, @value_format, @narrow_grid)}
      series={series(@chart, @url_fn)}
      y_axis_min={0}
      y_axis_max={@y_axis_max}
    />
    <.alert
      :if={truncated?(@chart)}
      status="warning"
      type="secondary"
      size="small"
      show_icon={false}
      title={@truncation_title}
    />
    """
  end

  @doc """
  Returns the ISO8601 representation of the scatter result's oldest entry, or
  an empty string when the result is not truncated. Callers pass this into their
  localized truncation message via `dgettext(..., date: scatter_oldest_entry_iso(...))`.
  """
  def scatter_oldest_entry_iso({:scatter, %{oldest_entry: %NaiveDateTime{} = entry}}), do: NaiveDateTime.to_iso8601(entry)
  def scatter_oldest_entry_iso(_), do: ""

  defp scatter?(%{result: {:scatter, _}, loading: loading}), do: !loading
  defp scatter?(_), do: false

  defp truncated?(%{result: {:scatter, %{truncated: true}}, loading: loading}), do: !loading
  defp truncated?(_), do: false

  defp series(%{result: {:scatter, data}}, url_fn) do
    Enum.map(data.series, fn series_item ->
      series_item
      |> Map.put(:itemStyle, %{opacity: 0.55})
      |> maybe_add_url(url_fn)
    end)
  end

  defp series(_, _), do: []

  defp maybe_add_url(series_item, nil), do: series_item

  defp maybe_add_url(series_item, url_fn) do
    Map.update!(series_item, :data, fn points ->
      Enum.map(points, &Map.put(&1, :url, url_fn.(&1)))
    end)
  end

  defp extra_options(period, value_format, narrow_grid?) do
    %{
      grid: grid(narrow_grid?),
      xAxis: x_axis(period),
      yAxis: y_axis(value_format),
      tooltip: %{trigger: "item", valueFormat: value_format},
      legend: %{show: false}
    }
  end

  defp grid(true), do: %{width: "93%", left: "0%", right: "7%", height: "88%", top: "5%"}
  defp grid(false), do: %{width: "97%", left: "0.4%", height: "88%", top: "5%"}

  defp x_axis({start_datetime, end_datetime}) do
    min_ts = DateTime.to_unix(start_datetime, :millisecond)
    max_ts = DateTime.to_unix(end_datetime, :millisecond)

    %{
      type: "value",
      min: min_ts,
      max: max_ts,
      interval: max_ts - min_ts,
      axisLabel: %{
        color: "var:noora-surface-label-secondary",
        formatter: "fn:toLocaleDate",
        padding: [10, 0, 0, 0]
      }
    }
  end

  defp y_axis(value_format) do
    %{
      splitNumber: 4,
      splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}},
      axisLabel: %{color: "var:noora-surface-label-secondary", formatter: value_format}
    }
  end
end
