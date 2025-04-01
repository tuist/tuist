defmodule TuistWeb.EmptyState do
  @moduledoc """
    A component that displays an empty state with a title, subtitle, and a command to run.
  """
  use TuistWeb, :live_component
  use TuistWeb.Noora
  attr :id, :string, required: true, doc: "The id of the empty state."
  attr :title, :string, required: true, doc: "The title of the empty state."
  attr :subtitle, :string, required: true, doc: "The subtitle of the empty state."

  attr :learn_more_href, :string,
    required: false,
    default: nil,
    doc: "The href of the learn more link."

  attr :command, :string, required: true, doc: "The command to run to populate the state."

  slot :light_background, required: true, doc: "The background of the empty state in light mode."
  slot :dark_background, required: true, doc: "The background of the empty state in dark mode."

  def empty_state(assigns) do
    ~H"""
    <div class="tuist-empty-state" id={@id}>
      <div data-part="background" data-style="light">
        {render_slot(@light_background)}
      </div>
      <div data-part="background" data-style="dark">
        {render_slot(@dark_background)}
      </div>
      <div data-part="terminal-card">
        <div data-part="header">
          <span data-part="title">{@title}</span>
          <span data-part="subtitle">
            <span data-part="label">
              {@subtitle}
            </span>
            <.link_button
              :if={@learn_more_href}
              label={gettext("Learn more")}
              underline
              size="medium"
              href={@learn_more_href}
              target="_blank"
            />
          </span>
        </div>
        <div data-part="terminal">
          <div data-part="header">
            <span data-part="title">
              {gettext("bash")}
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
      </div>
    </div>
    """
  end
end
