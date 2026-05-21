defmodule TuistWeb.MetricDropdownWidget do
  @moduledoc """
  A widget that displays a metric whose headline value can be switched between
  several named options via a dropdown (e.g. average vs. percentiles, or
  combined vs. per-action splits). Each option carries a colored dot, a label,
  and a formatted value.
  """
  use TuistWeb, :html
  use Noora

  import Phoenix.Component

  attr(:id, :string, required: true)
  attr(:title, :string, required: true)
  attr(:description, :string, required: true)
  attr(:value, :string, default: nil)
  attr(:options, :list, required: true, doc: "List of %{value, label, dot_type} maps")
  attr(:metrics, :map, default: nil, doc: "Map of option value (string) -> formatted metric")
  attr(:selected_type, :string, required: true)
  attr(:event_name, :string, required: true)
  attr(:loading, :boolean, default: false)
  attr(:empty, :boolean, default: false)
  attr(:empty_label, :string, default: nil)
  attr(:legend_color, :string, default: nil)
  attr(:selected, :boolean, default: false)
  attr(:trend_value, :any, default: nil)
  attr(:trend_type, :atom, default: :regular, values: [:regular, :inverse, :neutral])
  attr(:trend_label, :string, default: nil)
  attr(:phx_click, :string, default: nil)
  attr(:phx_value_widget, :string, default: nil)

  def metric_dropdown_widget(assigns) do
    ~H"""
    <.widget
      title={@title}
      description={@description}
      value={@value}
      id={@id}
      loading={@loading}
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
          :for={option <- @options}
          value={option.value}
          phx-click={@event_name}
          phx-value-type={option.value}
          data-selected={@selected_type == option.value}
        >
          <div data-part="percentile-item">
            <div data-part="dot" data-type={option.dot_type}></div>
            <span data-part="label">{option.label}</span>
            <span data-part="separator">-</span>
            <span data-part="value">
              {Map.get(@metrics || %{}, option.value, dgettext("dashboard", "N/A"))}
            </span>
          </div>
        </.dropdown_item>
      </:select>
    </.widget>
    """
  end
end
