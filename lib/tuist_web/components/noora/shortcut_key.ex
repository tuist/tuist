defmodule TuistWeb.Noora.ShortcutKey do
  @moduledoc false
  use Phoenix.Component

  attr :size, :string, values: ~w(small large), default: "large", doc: "Size of the shortcut key"

  slot :inner_block

  def shortcut_key(assigns) do
    ~H"""
    <kbd class="noora-shortcut-key" data-size={@size}>
      {render_slot(@inner_block)}
    </kbd>
    """
  end
end
