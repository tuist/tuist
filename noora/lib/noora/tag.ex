defmodule Noora.Tag do
  @moduledoc """
  A tag component.

  It can optionally be rendered with an icon and a button to dismiss it.

  ## Example

  ```elixir
  <.tag label="Active" />
  <.tag label="User" icon="user" />
  <.tag label="Beta" dismissible={true} on_dismiss="remove_tag" dismiss_value="beta" />
  ```
  """

  use Phoenix.Component

  import Noora.DismissIcon
  import Noora.Icon

  attr(:label, :string, required: true, doc: "The label of the tag.")
  attr(:dismissible, :boolean, default: false, doc: "Whether the tag can be dismissed.")
  attr(:on_dismiss, :string, default: nil, doc: "The event to trigger when the tag is dismissed.")
  attr(:dismiss_value, :string, default: nil, doc: "Value to pass to the dismiss event.")
  attr(:icon, :string, default: nil, doc: "An icon to render in front of the label.")
  attr(:disabled, :boolean, default: false, doc: "Whether the tag is disabled.")
  attr(:rest, :global)

  def tag(assigns) do
    ~H"""
    <div class="noora-tag" data-disabled={@disabled} aria-disabled={@disabled} {@rest}>
      <div :if={@icon} data-part="icon">
        <.icon name={@icon} />
      </div>
      <span data-part="label">{@label}</span>
      <.dismiss_icon
        :if={@dismissible}
        on_dismiss={@on_dismiss}
        disabled={@disabled}
        size="small"
        data-part="dismiss-icon"
        phx-value-data={@dismiss_value}
      />
    </div>
    """
  end

  attr(:label, :string, required: true, doc: "The label of the tag.")
  attr(:dismissible, :boolean, default: false, doc: "Whether the tag can be dismissed.")
  attr(:on_dismiss, :string, default: nil, doc: "The event to trigger when the tag is dismissed.")
  attr(:dismiss_value, :string, default: nil, doc: "Value to pass to the dismiss event.")
  attr(:disabled, :boolean, default: false, doc: "Whether the tag is disabled.")
  attr(:rest, :global)

  def input_tag(assigns) do
    ~H"""
    <div
      class="noora-tag"
      data-part="item"
      data-disabled={@disabled}
      aria-disabled={@disabled}
      {@rest}
    >
      <span data-part="item-preview">{@label}</span>
      <.dismiss_icon
        :if={@dismissible}
        on_dismiss={@on_dismiss}
        disabled={@disabled}
        size="small"
        data-part="item-delete-trigger"
        phx-value-data={@dismiss_value}
      />
    </div>
    """
  end
end
