defmodule TuistWeb.Components.Terminal do
  @moduledoc """
  A component that displays a terminal-like UI with a title, copy button,
  and command body.
  """
  use TuistWeb, :live_component
  use Noora

  attr :id, :string, required: true
  attr :title, :string, default: dgettext("dashboard", "bash")
  attr :command, :string, required: true

  def terminal(assigns) do
    ~H"""
    <div class="tuist-terminal">
      <div data-part="header">
        <span data-part="title">
          {@title}
        </span>
        <.neutral_button
          id={@id <> "-button"}
          size="small"
          phx-hook="Clipboard"
          data-clipboard-value={@command}
        >
          <.copy />
        </.neutral_button>
      </div>
      <div data-part="body">
        <span data-part="label">
          {@command}
        </span>
      </div>
    </div>
    """
  end
end
