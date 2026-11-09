defmodule Noora.Badge do
  @moduledoc """
  Renders a customizable badge component with various styles, colors, sizes, and optional icons or status indicators.
  """
  use Phoenix.Component

  import Noora.Icon
  import Noora.Utils

  @badge_appearances ~w(fill light-fill)
  @badge_colors ~w(neutral destructive warning attention success information focus primary secondary)
  @badge_sizes ~w(small large)

  def badge_appearances, do: @badge_appearances
  def badge_colors, do: @badge_colors
  def badge_sizes, do: @badge_sizes

  attr(:style, :string,
    values: @badge_appearances,
    default: "fill",
    doc: "Controls whether the badge uses a solid or light fill."
  )

  attr(:label, :string, required: true, doc: "The label of the badge")

  attr(:color, :string,
    values: @badge_colors,
    default: "neutral",
    doc: "Controls the semantic color. Disabled badges ignore this value."
  )

  attr(:size, :string,
    values: @badge_sizes,
    default: "small",
    doc: "Controls the badge dimensions and text size."
  )

  attr(:disabled, :boolean,
    default: false,
    doc: "Uses the disabled presentation regardless of color."
  )

  attr(:dot, :boolean,
    default: false,
    doc: "Displays a dot before the label when the icon slot is empty."
  )

  attr(:icon_only, :boolean,
    default: false,
    doc: "Hides the label and displays only the icon slot."
  )

  slot(:icon, doc: "The icon to render next to the label. Overrides the `dot` attribute.")

  attr(:rest, :global)

  def badge(assigns) do
    ~H"""
    <span
      class="noora-badge"
      data-style={@style}
      data-color={@color}
      data-size={@size}
      data-disabled={@disabled}
      data-dot={@dot}
      data-icon={has_slot_content?(@icon, assigns)}
      data-icon-only={@icon_only}
      {@rest}
    >
      <%= if @dot || has_slot_content?(@icon, assigns) do %>
        <div data-part="icon">
          <%= if has_slot_content?(@icon, assigns) do %>
            {render_slot(@icon)}
          <% else %>
            <.small_dot :if={@size == "small"} />
            <.large_dot :if={@size == "large"} />
          <% end %>
        </div>
      <% end %>
      <span :if={!@icon_only}>{@label}</span>
    </span>
    """
  end

  attr(:type, :string,
    values: ~w(icon dot),
    default: "icon",
    doc: "Whether to render the prefix as a dot, or a status-specific icon"
  )

  attr(:status, :string,
    values: ~w(success error warning attention disabled in_progress),
    required: true,
    doc: "The status of the badge"
  )

  attr(:label, :string, required: true, doc: "The label of the badge")
  attr(:rest, :global)

  def status_badge(assigns) do
    ~H"""
    <span class="noora-status-badge" data-status={@status} {@rest}>
      <span data-part="icon">
        <.status_icon :if={@type == "icon"} status={@status} />
        <.large_dot :if={@type == "dot"} />
      </span>
      <span data-part="label">{@label}</span>
    </span>
    """
  end

  def status_icon(%{status: "success"} = assigns) do
    ~H"""
    <.circle_check />
    """
  end

  def status_icon(%{status: "error"} = assigns) do
    ~H"""
    <.alert_circle />
    """
  end

  def status_icon(%{status: "warning"} = assigns) do
    ~H"""
    <.alert_hexagon />
    """
  end

  def status_icon(%{status: "attention"} = assigns) do
    ~H"""
    <.alert_triangle />
    """
  end

  def status_icon(%{status: "disabled"} = assigns) do
    ~H"""
    <.cancel />
    """
  end

  def status_icon(%{status: "in_progress"} = assigns) do
    ~H"""
    <.circle_dashed />
    """
  end

  defp small_dot(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 12 12" fill="none">
      <rect x="4" y="4" width="4" height="4" rx="1" fill="#FDFDFD" />
    </svg>
    """
  end

  defp large_dot(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16" fill="none">
      <rect x="5" y="5" width="6" height="6" rx="1.33333" fill="currentColor" />
    </svg>
    """
  end
end
