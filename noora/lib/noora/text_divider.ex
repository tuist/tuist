defmodule Noora.TextDivider do
  @moduledoc """
  A component for rendering a text divider.

  ## Example

  ```elixir
  <.text_divider text="OR" />
  <.text_divider text="Section 2" />
  ```
  """

  use Phoenix.Component

  attr(:text, :string,
    required: true,
    doc: "The text to display as the divider"
  )

  def text_divider(assigns) do
    ~H"""
    <span class="noora-text-divider">
      {@text}
    </span>
    """
  end
end
