defmodule TuistWeb.Noora.Button do
  @moduledoc """
  A component for rendering both standard buttons and link-style buttons, offering flexible styling options for variants, sizes, and icon placement.
  """

  use Phoenix.Component

  @button_variants ~w(primary secondary destructive)
  @button_sizes ~w(small medium large)

  def button_variants, do: @button_variants
  def button_sizes, do: @button_sizes

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

  attr :icon_only, :boolean, default: false, doc: "Determines if the button is icon only"

  slot :icon_left, doc: "Icon displayed on the left of an item"
  slot :icon_right, doc: "Icon displayed on the right of an item"
  slot :inner_block, required: false, doc: "Inner block that renders HEEx content"

  attr :rest, :global, include: ~w(phx-click)

  def button(assigns) do
    ~H"""
    <button
      class="noora-button"
      data-variant={@variant}
      data-size={@size}
      data-icon-only={@icon_only}
      {@rest}
    >
      <div data-part="spacer" />
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
      <div data-part="spacer" />
    </button>
    """
  end

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

  attr :underline, :boolean, default: false, doc: "Determines if the button is underlined"

  attr :rest, :global

  slot :icon_left, doc: "Icon displayed on the left of an item"
  slot :icon_right, doc: "Icon displayed on the right of an item"

  def link_button(assigns) do
    ~H"""
    <button
      class="noora-link-button"
      data-variant={@variant}
      data-size={@size}
      data-underline={@underline}
      {@rest}
    >
      <%= if @icon_left do %>
        {render_slot(@icon_left)}
      <% end %>
      <span>{@label}</span>
      <%= if @icon_right do %>
        {render_slot(@icon_right)}
      <% end %>
    </button>
    """
  end
end
