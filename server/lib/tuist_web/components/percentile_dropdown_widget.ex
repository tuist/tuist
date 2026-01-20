defmodule TuistWeb.PercentileDropdownWidget do
  @moduledoc """
  A widget component that displays metrics with a dropdown for selecting different percentile views.

  This component combines a display widget with a dropdown menu that allows users to switch between
  different statistical views of the same metric: average (avg), 99th percentile (p99),
  90th percentile (p90), and 50th percentile (p50).

  Each percentile option is displayed with a colored dot indicator, label, and corresponding value.
  The colors are defined in CSS using the `data-type` attribute:
  - avg: blue (--noora-chart-legend-secondary)
  - p99: green (--noora-chart-p99)
  - p90: pink (--noora-chart-p90)
  - p50: orange (--noora-chart-p50)

  ## Example

      <.percentile_dropdown_widget
        id="latency-widget"
        title="Latency"
        description="Response time"
        value="125ms"
        metrics=%{avg: "100ms", p99: "250ms", p90: "180ms", p50: "95ms"}
        selected_type="p99"
        event_name="change_percentile"
        legend_color="green"
        trend_value="+5%"
        trend_label="vs last week"
      />
  """
  use TuistWeb, :html
  use Noora

  import Phoenix.Component

  attr(:id, :string, required: true)
  attr(:title, :string, required: true)
  attr(:description, :string, required: true)
  attr(:value, :string, required: true)
  attr(:metrics, :map, required: true, doc: "Map containing the metric values (avg, p99, p90, p50)")
  attr(:selected_type, :string, required: true, values: ~w(avg p99 p90 p50))
  attr(:event_name, :string, required: true, doc: "Phoenix event name for selection changes")
  attr(:empty, :boolean, default: false)
  attr(:empty_label, :string, default: nil)
  attr(:legend_color, :string, default: nil)
  attr(:selected, :boolean, default: false)
  attr(:trend_value, :any, default: nil)
  attr(:trend_type, :atom, default: :regular, values: [:regular, :inverse, :neutral])
  attr(:trend_label, :string, default: nil)
  attr(:phx_click, :string, default: nil, doc: "Phoenix event to trigger on widget click")
  attr(:phx_value_widget, :string, default: nil, doc: "Widget ID value to pass with phx-click event")

  def percentile_dropdown_widget(assigns) do
    ~H"""
    <.widget
      title={@title}
      description={@description}
      value={@value}
      id={@id}
      empty={@empty}
      empty_label={@empty_label}
      legend_color={@legend_color}
      selected={@selected}
      trend_value={@trend_value}
      trend_type={@trend_type}
      trend_label={@trend_label}
      phx_click={@phx_click}
      phx_value_widget={@phx_value_widget}
    >
      <:select>
        <.dropdown_item
          value="avg"
          phx-click={@event_name}
          phx-value-type="avg"
          data-selected={@selected_type == "avg"}
        >
          <.percentile_dropdown_item type="avg" metrics={@metrics} />
        </.dropdown_item>
        <.dropdown_item
          value="p99"
          phx-click={@event_name}
          phx-value-type="p99"
          data-selected={@selected_type == "p99"}
        >
          <.percentile_dropdown_item type="p99" metrics={@metrics} />
        </.dropdown_item>
        <.dropdown_item
          value="p90"
          phx-click={@event_name}
          phx-value-type="p90"
          data-selected={@selected_type == "p90"}
        >
          <.percentile_dropdown_item type="p90" metrics={@metrics} />
        </.dropdown_item>
        <.dropdown_item
          value="p50"
          phx-click={@event_name}
          phx-value-type="p50"
          data-selected={@selected_type == "p50"}
        >
          <.percentile_dropdown_item type="p50" metrics={@metrics} />
        </.dropdown_item>
      </:select>
    </.widget>
    """
  end

  defp percentile_dropdown_item(assigns) do
    ~H"""
    <div data-part="percentile-item">
      <div data-part="dot" data-type={@type}></div>
      <span data-part="label">{percentile_label(@type)}</span>
      <span data-part="separator">-</span>
      <span data-part="value">
        {Map.get(@metrics, String.to_atom(@type), dgettext("dashboard", "N/A"))}
      </span>
    </div>
    """
  end

  defp percentile_label("avg"), do: dgettext("dashboard", "Avg.")
  defp percentile_label("p99"), do: dgettext("dashboard", "p99")
  defp percentile_label("p90"), do: dgettext("dashboard", "p90")
  defp percentile_label("p50"), do: dgettext("dashboard", "p50")
  defp percentile_label(_), do: dgettext("dashboard", "Avg.")
end
