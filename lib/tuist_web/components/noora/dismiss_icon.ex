defmodule TuistWeb.Noora.DismissIcon do
  @moduledoc false
  use Phoenix.Component

  alias TuistWeb.Noora.Icon

  attr :size, :string, values: ~w(small large), default: "large", doc: "The size of the icon"
  attr :rest, :global

  def dismiss_icon(assigns) do
    ~H"""
    <button class="noora-dismiss-icon" data-size={@size} {@rest}>
      <Icon.close />
    </button>
    """
  end
end
