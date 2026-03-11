defmodule Noora.Popover do
  @moduledoc """
  Renders a popover component with a trigger and customizable content.

  ## Example

  ```elixir
  <.popover id="settings-popover">
    <:trigger :let={attrs}>
      <button {attrs}>Settings</button>
    </:trigger>
    <div>
      <h3>Popover Content</h3>
      <p>This is the content inside the popover.</p>
    </div>
  </.popover>

  <.popover id="form-popover" placement="bottom-end">
    <:trigger :let={attrs}>
      <span {attrs}><.icon name="filter" /></span>
    </:trigger>
    <form phx-submit="save">
      <.text_input name="name" label="Name" />
      <.button type="submit" label="Save" />
    </form>
  </.popover>
  ```
  """
  use Phoenix.Component

  attr(:id, :string, required: true, doc: "Unique identifier for the popover")
  attr(:modal, :boolean, default: false, doc: "Enables focus trapping and interaction blocking outside the popover")
  attr(:auto_focus, :boolean, default: true, doc: "Automatically focuses first focusable element when opened")
  attr(:close_on_interact_outside, :boolean, default: true, doc: "Controls whether clicking outside closes the popover")
  attr(:close_on_escape, :boolean, default: true, doc: "Determines if pressing Escape closes the popover")

  attr(:placement, :string,
    default: "bottom",
    values: ~w(top top-start top-end bottom bottom-start bottom-end),
    doc: "Positioning placement: top, top-start, top-end, bottom, bottom-start, bottom-end"
  )

  attr(:on_open_change, :string, default: nil, doc: "Phoenix event to push when popover state changes")

  attr(:rest, :global, doc: "Additional HTML attributes")

  slot(:trigger, required: true, doc: "Trigger element for the popover")
  slot(:inner_block, required: true, doc: "Content to be rendered inside the popover")

  def popover(assigns) do
    ~H"""
    <div
      id={@id}
      class="noora-popover"
      phx-hook="NooraPopover"
      data-modal={@modal}
      data-auto-focus={@auto_focus}
      data-close-on-interact-outside={@close_on_interact_outside}
      data-close-on-escape={@close_on_escape}
      data-positioning-placement={@placement}
      data-on-open-change={@on_open_change}
      {@rest}
    >
      {render_slot(@trigger, %{"data-part" => "trigger"})}
      <div data-part="positioner">
        <div data-part="content">
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end
end
