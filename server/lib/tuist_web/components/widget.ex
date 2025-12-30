defmodule TuistWeb.Widget do
  @moduledoc """
  A reusable card-based widget component for displaying metrics and data visualizations.

  This component provides a consistent UI pattern for showing key metrics, statistics, or data points
  across the application. Widgets can display a value, optional trend information, and can be made
  interactive with click handlers.

  ## Features

  - **Value Display**: Shows a primary metric value with title and optional description
  - **Legend**: Color-coded legend indicator (primary, secondary, destructive, p99, p90, p50)
  - **Trend Indicators**: Shows trend changes with percentage values and custom labels
  - **Interactive**: Can be made clickable with Phoenix events
  - **Selection State**: Visual feedback when a widget is selected
  - **Empty State**: Special styling when no data is available
  - **Custom Select Slot**: Allows embedding custom select/dropdown controls

  ## Examples

  ### Basic Widget

      <.widget
        id="total-users"
        title="Total Users"
        value="1,234"
        legend_color="primary"
      />

  ### Widget with Trend

      <.widget
        id="response-time"
        title="Avg Response Time"
        value="125ms"
        legend_color="secondary"
        trend_value={-5}
        trend_label="vs last week"
        trend_type={:inverse}
      />

  ### Interactive Widget

      <.widget
        id="cache-hits"
        title="Cache Hits"
        value="98.5%"
        description="Percentage of requests served from cache"
        selected={@selected_widget == "cache-hits"}
        phx_click="select_widget"
        phx_value_widget="cache-hits"
      />

  ### Widget with Custom Select

      <.widget
        id="latency"
        title="Latency"
        value="250ms"
        legend_color="p99"
      >
        <:select>
          <.dropdown id="latency-dropdown">
            <.dropdown_item>p99</.dropdown_item>
            <.dropdown_item>p90</.dropdown_item>
          </.dropdown>
        </:select>
      </.widget>

  ### Empty Widget

      <.widget
        id="no-data"
        title="Analytics"
        value=""
        empty={true}
      />
  """
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

  attr(:trend_type, :atom,
    default: :regular,
    values: [:regular, :inverse, :neutral],
    doc:
      "The trend type: :regular (higher is better), :inverse (lower is better), or :neutral (no positive/negative connotation)."
  )

  attr(:selected, :boolean,
    default: false,
    doc: "Whether the widget is selected."
  )

  attr(:empty, :boolean, default: false, doc: "Whether the widget is empty")

  attr(:empty_label, :string, default: nil, doc: "Custom label to display when widget is empty")

  attr(:phx_click, :string, default: nil, doc: "Phoenix event to trigger on widget click")

  attr(:phx_value_widget, :string, default: nil, doc: "Widget ID value to pass with phx-click event")

  slot(:select, doc: "Optional select dropdown to display next to the title")

  def widget(assigns) do
    ~H"""
    <%= if @empty do %>
      <.card_section class="tuist-widget" id={@id} data-empty="true">
        <div data-part="background">
          <.empty_state_background />
        </div>
        <div data-part="header">
          <span data-part="title">{@title}</span>
        </div>
        <span data-part="empty-label">
          {if @empty_label, do: @empty_label, else: dgettext("dashboard", "No data yet")}
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
        <%= if @select != [] do %>
          <.dropdown
            id={"#{@id}-dropdown"}
            label={@title}
            phx-click={Phoenix.LiveView.JS.exec("event.stopPropagation()", to: "window")}
          >
            {render_slot(@select)}
          </.dropdown>
        <% else %>
          <div data-part="title">
            <span data-part="label">{@title}</span>
          </div>
        <% end %>
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
        <.trend_badge trend_value={@trend_value} trend_type={@trend_type} />
        <span data-part="label">{@trend_label}</span>
      </div>
    </.card_section>
    """
  end
end
