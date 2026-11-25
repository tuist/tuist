defmodule Noora.ContentDivider do
  @moduledoc """
  A component for separating groups of content, with a line or with a label alone.

  ## Example

  ```elixir
  <.content_divider />
  <.content_divider text="or" />
  <.content_divider variant="text" text="Today" />
  ```
  """

  use Phoenix.Component

  attr(:variant, :string,
    values: ~w(line text),
    default: "line",
    doc: "Whether the divider draws a line, or shows `text` alone without one."
  )

  attr(:text, :string,
    default: nil,
    doc:
      "The label, always shown in uppercase. The `line` variant splits the line around it; the `text` variant needs it, since it has no line."
  )

  attr(:rest, :global, doc: "Additional HTML attributes")

  def content_divider(assigns) do
    ~H"""
    <div class="noora-content-divider" data-variant={@variant} {@rest}>
      <span :if={@text} data-part="text">{@text}</span>
    </div>
    """
  end
end
