defmodule TuistWeb.Noora.DismissIcon do
  @moduledoc """
  Renders a dismiss icon button for closing or removing elements, with customizable size.
  """
  use Phoenix.Component

  import TuistWeb.Noora.Icon

  attr :size, :string, values: ~w(small large), default: "large", doc: "The size of the icon"
  attr :on_dismiss, :string, default: nil
  attr :rest, :global

  def dismiss_icon(assigns) do
    ~H"""
    <button
      class="noora-dismiss-icon"
      phx-click={@on_dismiss}
      data-size={@size}
      aria-label="Dismiss"
      {@rest}
    >
      <.close />
    </button>
    """
  end
end
