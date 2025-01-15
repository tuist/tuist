defmodule TuistWeb.Noora.Button do
  @moduledoc false

  use Phoenix.Component

  @button_variants ~w(primary secondary destructive)
  @button_sizes ~w(small medium large)

  @doc """
  The `button` component is used to create customizable buttons with various styles, icons, and indicators.
  """

  attr :label, :string, required: true, doc: "The label of the button"

  attr :variant, :string,
    values: @button_variants,
    default: "primary",
    doc: "Determines the style"

  attr :size, :string,
    values: @button_sizes,
    default: "large",
    doc:
      "Determines the overall size of the elements, including padding, font size, and other items"

  attr :disabled, :boolean, default: false, doc: "Determines if the button is disabled"

  attr :icon_only, :boolean, default: false, doc: "Determines if the button is icon only"

  slot :icon_left, doc: "Icon displayed on the left of an item"
  slot :icon_right, doc: "Icon displayed on the right of an item"
  slot :inner_block, required: false, doc: "Inner block that renders HEEx content"

  attr :rest, :global

  def button(assigns) do
    ~H"""
    <button
      class="noora-button"
      data-variant={@variant}
      data-size={@size}
      data-icon-only={@icon_only}
      disabled={@disabled}
      {@rest}
    >
      <%= if @icon_left  && !@icon_only do %>
        {render_slot(@icon_left)}
      <% end %>
      <span :if={!@icon_only}>{@label}</span>
      <%= if @icon_only do %>
        {render_slot(@inner_block)}
      <% end %>
      <%= if @icon_right && !@icon_only do %>
        {render_slot(@icon_right)}
      <% end %>
    </button>
    """
  end
end
