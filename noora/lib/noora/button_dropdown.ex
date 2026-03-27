defmodule Noora.ButtonDropdown do
  @moduledoc """
  A button with an attached dropdown menu, combining a primary action button with a dropdown trigger.

  The component renders a button that has a main clickable area and a separate dropdown trigger area,
  allowing users to perform a primary action or access additional options via a dropdown menu.

  ## Example

  ```elixir
  <.button_dropdown id="actions-menu" label="Button" size="large">
    <:icon_left><.chevron_left /></:icon_left>
    <:icon_right><.chevron_right /></:icon_right>
    <.dropdown_item label="Option 1" on_click="option_1" />
    <.dropdown_item label="Option 2" on_click="option_2" />
  </.button_dropdown>
  ```
  """

  use Phoenix.Component

  import Noora.Icon
  import Noora.Utils

  @button_sizes ~w(medium large)

  def button_sizes, do: @button_sizes

  attr(:id, :string, required: true, doc: "Unique identifier for the dropdown component")
  attr(:label, :string, required: true, doc: "The label of the button")

  attr(:size, :string,
    values: @button_sizes,
    default: "large",
    doc: "Determines the overall size of the elements, including padding, font size, and other items"
  )

  attr(:disabled, :boolean, default: false, doc: "Whether the button dropdown is disabled")

  attr(:on_open_change, :string, default: nil, doc: "Event handler for when the dropdown opens")

  attr(:on_highlight_change, :string,
    default: nil,
    doc: "Event handler for when the highlighted option changes"
  )

  attr(:on_select, :string, default: nil, doc: "Event handler for when an option is selected")

  attr(:on_escape_key_down, :string,
    default: nil,
    doc: "Event handler for when the escape key is pressed"
  )

  attr(:on_pointer_down_outside, :string,
    default: nil,
    doc: "Event handler for when the pointer is pressed outside the dropdown"
  )

  attr(:on_focus_outside, :string,
    default: nil,
    doc: "Function called when the focus is moved outside the component"
  )

  attr(:on_interact_outside, :string,
    default: nil,
    doc: "Function called when an interaction happens outside the component"
  )

  attr(:close_on_select, :boolean,
    default: true,
    doc: "Whether to close the dropdown when an item is selected"
  )

  attr(:align, :string,
    values: ~w(start end),
    default: "start",
    doc: "Alignment of the dropdown menu relative to the button"
  )

  attr(:rest, :global, include: ~w(phx-click), doc: "Additional HTML attributes for the main button")

  slot(:icon_left, doc: "Icon displayed on the left of the label")
  slot(:icon_right, doc: "Icon displayed on the right of the label")
  slot(:inner_block, doc: "Content to be rendered inside the dropdown menu")

  def button_dropdown(assigns) do
    ~H"""
    <.portal id={@id <> "-content-portal"} target={"#" <> @id <> "-content-target"}>
      {render_slot(@inner_block)}
    </.portal>
    <div
      id={@id}
      class="noora-button-dropdown"
      phx-hook="NooraDropdown"
      phx-update="ignore"
      data-size={@size}
      data-loop-focus
      data-typeahead
      data-close-on-select={@close_on_select}
      data-on-open-change={@on_open_change}
      data-on-highlight-change={@on_highlight_change}
      data-on-select={@on_select}
      data-on-escape-key-down={@on_escape_key_down}
      data-on-pointer-down-outside={@on_pointer_down_outside}
      data-on-focus-outside={@on_focus_outside}
      data-on-interact-outside={@on_interact_outside}
      data-align={@align}
    >
      <button data-part="main-button" disabled={@disabled} type="button" {@rest}>
        <div :if={has_slot_content?(@icon_left, assigns)} data-part="icon-left">
          {render_slot(@icon_left)}
        </div>
        <span data-part="label">{@label}</span>
        <div :if={has_slot_content?(@icon_right, assigns)} data-part="icon-right">
          {render_slot(@icon_right)}
        </div>
      </button>
      <button data-part="trigger" disabled={@disabled} type="button">
        <div data-part="indicator">
          <.chevron_down />
        </div>
      </button>
      <div data-part="positioner">
        <div class="noora-dropdown-content" data-part="content">
          <div id={@id <> "-content-target"} data-part="items"></div>
        </div>
      </div>
    </div>
    """
  end
end
