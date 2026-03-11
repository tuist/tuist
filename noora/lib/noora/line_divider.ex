defmodule Noora.LineDivider do
  @moduledoc """
  A component for rendering a line divider.

  ## Example

  ```elixir
  <.line_divider text="or" />
  ```
  """

  use Phoenix.Component

  attr(:text, :string,
    required: false,
    default: nil,
    doc: "The text to display in the line divider"
  )

  attr(:rest, :global, doc: "Additional HTML attributes")

  def line_divider(assigns) do
    ~H"""
    <div class="noora-line-divider" {@rest}>
      <div data-part="line"></div>
      <span :if={@text} data-part="text">{@text}</span>
      <div data-part="line"></div>
    </div>
    """
  end
end
