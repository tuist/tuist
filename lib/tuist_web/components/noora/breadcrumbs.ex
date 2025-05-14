defmodule TuistWeb.Noora.Breadcrumbs do
  @moduledoc """
  Renders a breadcrumbs component with.
  """
  use Phoenix.Component

  import TuistWeb.Noora.Avatar
  import TuistWeb.Noora.Dropdown
  import TuistWeb.Noora.Icon
  import TuistWeb.Noora.Utils

  attr :style, :string, values: ~w(slash arrow), default: "slash"
  slot :inner_block
  attr :rest, :global

  def breadcrumbs(assigns) do
    ~H"""
    <div class="noora-breadcrumbs" data-style={@style} {@rest}>
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

  attr :show_avatar, :boolean, default: false, doc: "Whether to show the avatar"

  attr :avatar_color, :string,
    values: ~w(gray red orange yellow azure blue purple pink),
    default: "pink",
    doc: "Color of the avatar when avatar is shown"

  slot :icon, doc: "Breadcrumb icon"
  slot :inner_block, doc: "Content to be rendered inside the breadcrumb menu"
  attr :rest, :global

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
      {@rest}
    >
      <button data-part="trigger">
        <.avatar
          :if={@show_avatar}
          id={@id <> "-avatar"}
          name={@label}
          color={@avatar_color}
          size="2xsmall"
          data-part="avatar"
        />
        <div :if={has_slot_content?(@icon, assigns) and not @show_avatar} data-part="icon">
          {render_slot(@icon)}
        </div>
        <span data-part="label">{@label}</span>
        <div :if={has_slot_content?(@inner_block, assigns)} data-part="selector">
          <.selector />
        </div>
      </button>
      <div :if={has_slot_content?(@inner_block, assigns)} data-part="positioner">
        <div class="noora-dropdown-content" data-part="content">
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>

    <div data-part="slash"><.slash /></div>
    <div data-part="arrow"><.chevron_right /></div>
    """
  end

  attr :id, :string, required: false
  attr :label, :string, required: true, doc: "Text displayed as the main content of the item"
  attr :value, :string, required: true, doc: "Value associated with the breadcrumb item"
  attr :selected, :boolean, default: false, doc: "Whether the item is selected"
  attr :href, :string, default: nil, doc: "Standard URL for navigation"
  attr :show_avatar, :boolean, default: false, doc: "Whether to show the avatar"

  attr :avatar_color, :string,
    values: ~w(gray red orange yellow azure blue purple pink),
    default: "pink",
    doc: "Color of the avatar when avatar is shown"

  def breadcrumb_item(assigns) do
    ~H"""
    <.dropdown_item value={@value} label={@label} href={@href} data-selected={@selected}>
      <:left_icon>
        <.avatar
          :if={@show_avatar}
          id={(@id || @label) <> "-avatar"}
          name={@label}
          color={@avatar_color}
          size="2xsmall"
          data-part="avatar"
        />
      </:left_icon>
      <:right_icon><.check /></:right_icon>
    </.dropdown_item>
    """
  end
end
