defmodule TuistWeb.Widget do
  @moduledoc false
  use Phoenix.Component
  use Gettext, backend: TuistWeb.Gettext
  use Noora

  import TuistWeb.Components.EmptyStateBackground
  import TuistWeb.Components.TrendBadge

  attr(:id, :string, required: true, doc: "The id of the widget.")
  attr(:title, :string, required: true, doc: "The title of the widget.")

  attr(:legend_color, :string,
    values: ~w(primary secondary destructive p99 p90 p50),
    required: false,
    doc: "The color of the legend. The legend is hidden if the value is `nil`."
  )

  attr(:description, :string,
    required: false,
    doc: "The description of the widget value.",
    default: nil
  )

  attr(:value, :string, required: true, doc: "The value of the widget.")

  attr(:trend_value, :integer,
    required: false,
    default: nil,
    doc: "The trend value of the widget."
  )

  attr(:trend_label, :string, required: false, doc: "The trend label of the widget.")

  attr(:trend_inverse, :boolean,
    default: false,
    doc: "Set this to true when smaller number means the trend is positive."
  )

  attr(:selected, :boolean,
    default: false,
    doc: "Whether the widget is selected."
  )

  attr(:empty, :boolean, default: false, doc: "Whether the widget is empty")

  attr(:phx_click, :string, default: nil, doc: "Phoenix event to trigger on widget click")

  attr(:phx_value_widget, :string, default: nil, doc: "Widget ID value to pass with phx-click event")

  slot(:select, doc: "Optional select dropdown to display next to the title")

  def widget(assigns) do
    ~H"""
    <%= if @empty do %>
      <.card_section class="tuist-widget" id={@id}>
        <div data-part="background">
          <.empty_state_background />
        </div>
        <div data-part="header">
          <span data-part="title">{@title}</span>
        </div>
        <span data-part="empty-label">
          {gettext("No data yet")}
        </span>
      </.card_section>
    <% else %>
      <div
        :if={@phx_click}
        role="button"
        tabindex="0"
        phx-click={@phx_click}
        phx-value-widget={@phx_value_widget}
        phx-key="Enter"
        data-selected={@selected}
        class="tuist-widget-link"
      >
        <.static_widget {assigns} />
      </div>
      <.static_widget :if={!@phx_click} {assigns} />
    <% end %>
    """
  end

  defp static_widget(assigns) do
    ~H"""
    <.card_section class="tuist-widget" id={@id}>
      <div data-part="header">
        <div
          :if={not is_nil(Map.get(assigns, :legend_color))}
          data-color={@legend_color}
          data-part="legend"
        >
        </div>
        <div data-part="title">
          <span data-part="label">{@title}</span>
          {render_slot(@select)}
        </div>
        <.tooltip
          :if={@description}
          id={@id <> "-tooltip"}
          title={@title}
          description={@description}
          size="large"
        >
          <:trigger :let={attrs}>
            <span {attrs} data-part="tooltip-icon">
              <.alert_circle />
            </span>
          </:trigger>
        </.tooltip>
      </div>
      <span data-part="value">{@value}</span>
      <div :if={@trend_value} data-part="trend">
        <.trend_badge trend_value={@trend_value} trend_inverse={@trend_inverse} />
        <span data-part="label">{@trend_label}</span>
      </div>
    </.card_section>
    """
  end
end
