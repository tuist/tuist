defmodule TuistWeb.Noora.Dropdown do
  @moduledoc false
  use Phoenix.Component

  import TuistWeb.Noora.Icon
  import TuistWeb.Noora.Utils

  attr :id, :string, required: true, doc: "Unique identifier for the dropdown component"
  attr :label, :string, required: true, doc: "Main text displayed in the dropdown trigger"

  attr :secondary_text, :string,
    default: nil,
    doc: "Secondary text displayed to the left of the main label"

  attr :hint, :string, default: nil, doc: "Hint text for the dropdown"

  attr :disabled, :boolean, default: nil, doc: "Whether the dropdown is disabled"

  attr :on_open_change, :string, default: nil, doc: "Event handler for when the dropdown opens"

  attr :on_highlight_change, :string,
    default: nil,
    doc: "Event handler for when the highlighted option changes"

  attr :on_select, :string, default: nil, doc: "Event handler for when an option is selected"

  attr :on_escape_key_down, :string,
    default: nil,
    doc: "Event handler for when the escape key is pressed"

  attr :on_pointer_down_outside, :string,
    default: nil,
    doc: "Event handler for when the pointer is pressed outside the dropdown"

  attr :on_focus_outside, :string,
    default: nil,
    doc: "Function called when the focus is moved outside the component"

  attr :on_interact_outside, :string,
    default: nil,
    doc: "Function called when an interaction happens outside the component"

  slot :icon, doc: "Icon to be rendered in the dropdown trigger"
  slot :inner_block, doc: "Content to be rendered inside the dropdown menu"

  def dropdown(assigns) do
    ~H"""
    <div
      id={@id}
      class="noora-dropdown"
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
    >
      <button data-part="trigger" disabled={@disabled}>
        <div class="noora-dropdown__label-wrapper">
          <div :if={has_slot_content?(@icon, assigns)} class="noora-dropdown__icon">
            {render_slot(@icon)}
          </div>
          <span :if={@secondary_text} class="noora-dropdown__secondary_text">{@secondary_text}</span>
          <span class="noora-dropdown__label">{@label}</span>
        </div>
        <div data-part="indicator">
          <div class="noora-dropdown__indicator noora-dropdown__indicator_down">
            <.chevron_down />
          </div>
          <div class="noora-dropdown__indicator noora-dropdown__indicator_up">
            <.chevron_up />
          </div>
        </div>
      </button>
      <div data-part="positioner">
        <div data-part="content">
          {render_slot(@inner_block)}
        </div>
      </div>
      <span :if={@hint} class="noora-dropdown__hint">
        <.info_circle />
        <span>{@hint}</span>
      </span>
    </div>
    """
  end

  attr :value, :string, required: true, doc: "Value associated with the dropdown item"
  attr :patch, :string, default: nil, doc: "Phoenix LiveView patch navigation path"
  attr :navigate, :string, default: nil, doc: "Phoenix LiveView navigation path"
  attr :href, :string, default: nil, doc: "Standard URL for navigation"
  attr :size, :string, values: ~w(small large), default: "small", doc: "Size of the dropdown item"
  attr :label, :string, required: true, doc: "Text displayed as the main content of the item"

  attr :secondary_text, :string,
    default: nil,
    doc: "Secondary text displayed in parentheses after the label"

  attr :description, :string,
    default: nil,
    doc: "Additional description text (only visible when size is 'large')"

  attr :right_icon, :boolean,
    default: true,
    doc: "Controls visibility of the right chevron icon"

  attr :rest, :global, doc: "Additional HTML attributes"

  slot :left_icon,
    required: false,
    doc: "Optional slot for rendering an icon on the left side of the item"

  def dropdown_item(assigns) do
    ~H"""
    <.link
      data-part="item"
      data-value={@value}
      patch={@patch}
      navigate={@navigate}
      href={@href}
      data-size={@size}
    >
      <div :if={has_slot_content?(@left_icon, assigns)} class="noora-dropdown__item__left_icon">
        {render_slot(@left_icon)}
      </div>
      <div class="noora-dropdown__item__content">
        <div>
          <span class="noora-dropdown__item__label">{@label}</span>
          <span :if={@secondary_text} class="noora-dropdown__item__secondary_text">
            ({@secondary_text})
          </span>
        </div>
        <div :if={@size == "large"}>
          <span class="noora-dropdown__item__description">
            hallo {@description}
          </span>
        </div>
      </div>

      <div :if={@right_icon} class="noora-dropdown__item__right_icon"><.chevron_right /></div>
    </.link>
    """
  end
end
