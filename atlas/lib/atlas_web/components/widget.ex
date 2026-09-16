defmodule AtlasWeb.Widget do
  @moduledoc """
  Compact KPI tile used at the top of overview screens. Inspired by the
  Tuist dashboard widget: a colored legend bar, a title, a big value,
  and optional supporting copy or info tooltip.
  """
  use Phoenix.Component
  use Noora

  attr :id, :string, required: true
  attr :title, :string, required: true

  attr :value, :string, default: nil, doc: "The headline value rendered large."

  attr :description, :string, default: nil, doc: "Secondary copy rendered under the value."

  attr :tooltip_description, :string,
    default: nil,
    doc: "When set, renders an info icon next to the title with this text inside a Noora tooltip."

  attr :legend_color, :string,
    default: nil,
    doc:
      "Color of the legend bar shown next to the title. Hidden when nil. One of: primary, secondary, attention, warning, destructive, success, neutral."

  attr :empty, :boolean,
    default: false,
    doc: "Renders the empty state when there's no data to show."

  attr :empty_label, :string, default: nil, doc: "Custom empty-state label."

  attr :trend_value, :float,
    default: nil,
    doc: "Percentage change rendered as a colored trend badge under the value. Hidden when nil."

  attr :trend_label, :string,
    default: nil,
    doc: "Caption shown next to the trend badge, e.g. \"since last month\"."

  attr :trend_type, :atom,
    default: :regular,
    values: [:regular, :inverse, :neutral],
    doc: "How to color the trend: :regular (up is good), :inverse (down is good), or :neutral (no connotation)."

  attr :phx_click, :string,
    default: nil,
    doc: "Phoenix event triggered when the widget is clicked. Makes the widget behave as a button."

  attr :phx_value_widget, :string,
    default: nil,
    doc: "Value passed alongside the phx-click event. Use to identify which widget was selected."

  attr :selected, :boolean,
    default: false,
    doc: "Marks the widget as the currently selected option (used with phx_click)."

  attr :rest, :global

  def widget(assigns) do
    ~H"""
    <%= if @phx_click do %>
      <div
        role="button"
        tabindex="0"
        phx-click={@phx_click}
        phx-value-widget={@phx_value_widget}
        phx-key="Enter"
        data-selected={@selected}
        data-part="widget-link"
      >
        <.static_widget {assigns} />
      </div>
    <% else %>
      <.static_widget {assigns} />
    <% end %>
    """
  end

  defp static_widget(assigns) do
    ~H"""
    <.card_section id={@id} data-empty={@empty} data-part="widget" {@rest}>
      <div data-part="header">
        <div :if={@legend_color} data-color={@legend_color} data-part="legend"></div>
        <span data-part="title">{@title}</span>
        <div :if={@tooltip_description} data-part="tooltip">
          <.tooltip
            id={@id <> "-tooltip"}
            size="large"
            title={@title}
            description={@tooltip_description}
          >
            <:trigger :let={attrs}>
              <span {attrs}>
                <span data-part="tooltip-icon">
                  <.alert_circle />
                </span>
              </span>
            </:trigger>
          </.tooltip>
        </div>
      </div>
      <%= if @empty do %>
        <span data-part="empty-label">
          {@empty_label || "No data"}
        </span>
      <% else %>
        <span data-part="value">{@value}</span>
        <div :if={not is_nil(@trend_value)} data-part="trend">
          <.trend_badge trend_value={@trend_value} trend_type={@trend_type} />
          <span :if={@trend_label} data-part="trend-label">{@trend_label}</span>
        </div>
        <span :if={@description} data-part="description">{@description}</span>
      <% end %>
    </.card_section>
    """
  end

  attr :trend_value, :float, required: true
  attr :trend_type, :atom, default: :regular, values: [:regular, :inverse, :neutral]

  defp trend_badge(assigns) do
    rounded = Float.round(assigns.trend_value, 1)

    formatted =
      if abs(rounded) < 0.1 and rounded != 0.0 do
        "0.0"
      else
        :erlang.float_to_binary(rounded, decimals: if(abs(rounded) >= 1000, do: 0, else: 1))
      end

    assigns = assign(assigns, :formatted, formatted)

    ~H"""
    <.badge
      size="large"
      style="light-fill"
      label={if @trend_value > 0, do: "+#{@formatted}%", else: "#{@formatted}%"}
      color={trend_color(@trend_value, @trend_type)}
    >
      <:icon :if={@trend_value != 0}>
        <.trending_up :if={@trend_value > 0} />
        <.trending_down :if={@trend_value < 0} />
      </:icon>
    </.badge>
    """
  end

  defp trend_color(_value, :neutral), do: "neutral"
  defp trend_color(value, :regular) when value < 0, do: "destructive"
  defp trend_color(value, :inverse) when value < 0, do: "success"
  defp trend_color(value, :regular) when value > 0, do: "success"
  defp trend_color(value, :inverse) when value > 0, do: "destructive"
  defp trend_color(_value, _type), do: "neutral"
end
