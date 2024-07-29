defmodule TuistWeb.MarketingLayoutComponents do
  @moduledoc ~S"""
  A collection of components that are used from the layouts.
  """
  use TuistWeb, :live_component

  @default_icon_size 24

  embed_templates "marketing_layout_components/*"

  slot :inner_block, required: true

  def primary_small_button(assigns) do
    ~H"""
    <a class="marketing__component__primary__small__button font-xxs-strong">
      <%= render_slot(@inner_block) %>
    </a>
    """
  end

  attr :size, :integer, default: @default_icon_size
  attr :class, :string, default: ""

  def icon_plus(assigns) do
    ~H"""
    <svg
      class={@class}
      width={@size}
      height={@size}
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M12 5V19M5 12H19"
        stroke="black"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  attr :size, :integer, default: @default_icon_size
  attr :class, :string, default: ""

  def icon_minus(assigns) do
    ~H"""
    <svg
      class={@class}
      width={@size}
      height={@size}
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M5 12H19"
        stroke="black"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end
end
