defmodule TuistWeb.Noora.Badge do
  @moduledoc false
  use Phoenix.Component

  import TuistWeb.Noora.Utils

  attr :style, :string,
    values: ~w(fill light-fill),
    default: "fill",
    doc: "The style of the badge"

  attr :label, :string, required: true, doc: "The label of the badge"

  attr :color, :string,
    values: ~w(neutral destructive warning attention success information focus primary secondary),
    default: "neutral",
    doc: "The color of the badge"

  attr :size, :string, values: ~w(small large), default: "small", doc: "The size of the badge"

  attr :disabled, :boolean,
    default: false,
    doc: "Whether the badge is disabled. Overrides the `color` attribute."

  attr :dot, :boolean, default: false, doc: "Whether to render a dot on the side of the label."

  slot :icon, doc: "The icon to render next to the label. Overrides the `dot` attribute."

  attr :rest, :global

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
      {@rest}
    >
      <%= if @dot || has_slot_content?(@icon, assigns) do %>
        <div class="noora-badge__icon">
          <%= if has_slot_content?(@icon, assigns) do %>
            {render_slot(@icon)}
          <% else %>
            <.dot />
          <% end %>
        </div>
      <% end %>
      {@label}
    </span>
    """
  end

  defp dot(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 12 12" fill="currentColor">
      <rect x="4" y="4" width="4" height="4" rx="1" />
    </svg>
    """
  end
end
