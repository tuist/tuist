defmodule TuistWeb.SplitDropdownWidget do
  @moduledoc """
  A widget component that displays a combined metric with a dropdown for switching
  between the combined view and the two component sides of a split (e.g. downloads
  and uploads, read and write).
  """
  use TuistWeb, :html
  use Noora

  import Phoenix.Component

  attr(:id, :string, required: true)
  attr(:title, :string, required: true)
  attr(:description, :string, required: true)
  attr(:value, :string, default: nil)
  attr(:metrics, :map, default: nil, doc: "Map with :combined, :primary, :secondary formatted values")
  attr(:selected_type, :string, required: true, values: ~w(combined primary secondary))
  attr(:primary_value, :string, required: true, doc: "Dropdown value sent for the primary side")
  attr(:secondary_value, :string, required: true, doc: "Dropdown value sent for the secondary side")
  attr(:combined_label, :string, default: "Combined")
  attr(:primary_label, :string, required: true)
  attr(:secondary_label, :string, required: true)
  attr(:combined_dot, :string, default: "combined")
  attr(:primary_dot, :string, required: true)
  attr(:secondary_dot, :string, required: true)
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

  def split_dropdown_widget(assigns) do
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
          value="combined"
          phx-click={@event_name}
          phx-value-type="combined"
          data-selected={@selected_type == "combined"}
        >
          <.split_dropdown_item
            type={@combined_dot}
            label={@combined_label}
            value={Map.get(@metrics || %{}, :combined, dgettext("dashboard", "N/A"))}
          />
        </.dropdown_item>
        <.dropdown_item
          value={@primary_value}
          phx-click={@event_name}
          phx-value-type={@primary_value}
          data-selected={@selected_type == @primary_value}
        >
          <.split_dropdown_item
            type={@primary_dot}
            label={@primary_label}
            value={Map.get(@metrics || %{}, :primary, dgettext("dashboard", "N/A"))}
          />
        </.dropdown_item>
        <.dropdown_item
          value={@secondary_value}
          phx-click={@event_name}
          phx-value-type={@secondary_value}
          data-selected={@selected_type == @secondary_value}
        >
          <.split_dropdown_item
            type={@secondary_dot}
            label={@secondary_label}
            value={Map.get(@metrics || %{}, :secondary, dgettext("dashboard", "N/A"))}
          />
        </.dropdown_item>
      </:select>
    </.widget>
    """
  end

  defp split_dropdown_item(assigns) do
    ~H"""
    <div data-part="percentile-item">
      <div data-part="dot" data-type={@type}></div>
      <span data-part="label">{@label}</span>
      <span data-part="separator">-</span>
      <span data-part="value">{@value}</span>
    </div>
    """
  end
end
