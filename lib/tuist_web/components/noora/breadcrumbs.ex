defmodule TuistWeb.Noora.Breadcrumbs do
  @moduledoc """
  Renders a breadcrumbs component with.
  """
  use Phoenix.Component

  import TuistWeb.Noora.Icon
  import TuistWeb.Noora.Utils
  import TuistWeb.Noora.Dropdown

  attr :style, :string, values: ~w(slash arrow), default: "slash"

  def breadcrumbs(assigns) do
    ~H"""
    <div class="noora-breadcrumbs" data-style={@style}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :id, :string, required: true, doc: "Unique identifier for the breadcrumb component"
  attr :label, :string, required: true, doc: "Main text displayed in the breadcrumb trigger"

  attr :on_open_change, :string, default: nil, doc: "Event handler for when the breadcrumb opens"

  attr :on_highlight_change, :string,
    default: nil,
    doc: "Event handler for when the highlighted option changes"

  attr :on_select, :string, default: nil, doc: "Event handler for when an option is selected"

  attr :on_escape_key_down, :string,
    default: nil,
    doc: "Event handler for when the escape key is pressed"

  attr :on_pointer_down_outside, :string,
    default: nil,
    doc: "Event handler for when the pointer is pressed outside the breadcrumb"

  attr :on_focus_outside, :string,
    default: nil,
    doc: "Function called when the focus is moved outside the component"

  attr :on_interact_outside, :string,
    default: nil,
    doc: "Function called when an interaction happens outside the component"

  slot :icon, doc: "Breadcrumb icon"
  slot :inner_block, doc: "Content to be rendered inside the breadcrumb menu"

  def breadcrumb(assigns) do
    ~H"""
    <div
      id={@id}
      class="noora-breadcrumb"
      phx-hook="NooraDropdown"
      data-loop-focus
      data-close-on-select
      data-typeahead
      data-on-open-change={@on_open_change}
      data-on-highlight-change={@on_highlight_change}
      data-on-select={@on_select}
      data-on-escape-key-down={@on_escape_key_down}
      data-on-pointer-down-outside={@on_pointer_down_outside}
      data-on-focus-outside={@on_focus_outside}
      data-on-interact-outside={@on_interact_outside}
      data-positioning-offset-main-axis={6}
    >
      <button data-part="trigger">
        <div :if={has_slot_content?(@icon, assigns)} data-part="icon">
          {render_slot(@icon)}
        </div>
        <span data-part="label">{@label}</span>
        <div data-part="selector">
          <.selector />
        </div>
      </button>
      <div data-part="positioner">
        <div class="noora-dropdown-content" data-part="content">
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>

    <div data-part="slash"><.slash /></div>
    <div data-part="arrow"><.chevron_right /></div>
    """
  end

  attr :label, :string, required: true, doc: "Text displayed as the main content of the item"
  attr :value, :string, required: true, doc: "Value associated with the breadcrumb item"
  attr :selected, :boolean, default: false, doc: "Whether the item is selected"
  attr :href, :string, default: nil, doc: "Standard URL for navigation"

  def breadcrumb_item(assigns) do
    ~H"""
    <.dropdown_item
      value={@value}
      label={@label}
      href={@href}
      data-selected={@selected}
    >
      <:right_icon><.check /></:right_icon>
    </.dropdown_item>
    """
  end
end
