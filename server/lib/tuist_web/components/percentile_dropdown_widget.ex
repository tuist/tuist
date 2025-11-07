defmodule TuistWeb.PercentileDropdownWidget do
  @moduledoc false
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
  attr(:legend_color, :string, default: nil)
  attr(:selected, :boolean, default: false)
  attr(:trend_value, :any, default: nil)
  attr(:trend_inverse, :boolean, default: false)
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
      legend_color={@legend_color}
      selected={@selected}
      trend_value={@trend_value}
      trend_inverse={@trend_inverse}
      trend_label={@trend_label}
      phx_click={@phx_click}
      phx_value_widget={@phx_value_widget}
    >
      <:select>
        <.dropdown
          id={"#{@id}-dropdown"}
          icon_only
          label={get_percentile_label(@selected_type)}
        >
          <:icon><.chevron_down /></:icon>
          <.dropdown_item
            value="avg"
            phx-click={@event_name}
            phx-value-type="avg"
            data-selected={@selected_type == "avg"}
          >
            <.percentile_dropdown_item
              type="avg"
              metrics={@metrics}
            />
          </.dropdown_item>
          <.dropdown_item
            value="p99"
            phx-click={@event_name}
            phx-value-type="p99"
            data-selected={@selected_type == "p99"}
          >
            <.percentile_dropdown_item
              type="p99"
              metrics={@metrics}
            />
          </.dropdown_item>
          <.dropdown_item
            value="p90"
            phx-click={@event_name}
            phx-value-type="p90"
            data-selected={@selected_type == "p90"}
          >
            <.percentile_dropdown_item
              type="p90"
              metrics={@metrics}
            />
          </.dropdown_item>
          <.dropdown_item
            value="p50"
            phx-click={@event_name}
            phx-value-type="p50"
            data-selected={@selected_type == "p50"}
          >
            <.percentile_dropdown_item
              type="p50"
              metrics={@metrics}
            />
          </.dropdown_item>
        </.dropdown>
      </:select>
    </.widget>
    """
  end

  defp percentile_dropdown_item(assigns) do
    ~H"""
    <div data-part="percentile-item">
      <div data-part="dot" data-color={get_percentile_color(assigns.type)}></div>
      <span data-part="label">{get_percentile_label(assigns.type)}</span>
      <span data-part="separator">-</span>
      <span data-part="value">
        {Map.get(assigns.metrics, String.to_atom(assigns.type), "N/A")}
      </span>
    </div>
    """
  end

  defp get_percentile_label("avg"), do: gettext("Avg.")
  defp get_percentile_label("p99"), do: "p99"
  defp get_percentile_label("p90"), do: "p90"
  defp get_percentile_label("p50"), do: "p50"
  defp get_percentile_label(_), do: gettext("Avg.")

  defp get_percentile_color("avg"), do: "blue"
  defp get_percentile_color("p99"), do: "green"
  defp get_percentile_color("p90"), do: "pink"
  defp get_percentile_color("p50"), do: "orange"
  defp get_percentile_color(_), do: "blue"
end
