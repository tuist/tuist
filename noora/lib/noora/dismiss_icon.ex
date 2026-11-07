defmodule Noora.DismissIcon do
  @moduledoc """
  Renders a dismiss icon button for closing or removing elements, with customizable size.

  ## Example

  ```elixir
  <.dismiss_icon size="small" on_dismiss="hide-banner" />
  ```
  """
  use Phoenix.Component

  import Noora.Icon

  attr(:size, :string, values: ~w(small large), default: "large", doc: "The size of the icon")
  attr(:on_dismiss, :string, default: nil, doc: "Event to trigger when the dismiss icon is clicked")
  attr(:type, :string, default: "button", doc: "The type of the button")
  attr(:rest, :global, include: ~w(disabled form), doc: "Additional HTML attributes")

  def dismiss_icon(assigns) do
    ~H"""
    <button
      class="noora-dismiss-icon"
      phx-click={@on_dismiss}
      data-size={@size}
      aria-label="Dismiss"
      type={@type}
      {@rest}
    >
      <.close />
    </button>
    """
  end
end
