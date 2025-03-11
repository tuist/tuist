defmodule TuistWeb.Noora.LineDivider do
  @moduledoc """
  A component for rendering a line divider.
  """

  use Phoenix.Component

  attr :text, :string,
    required: false,
    default: nil,
    doc: "The text to display in the line divider"

  def line_divider(assigns) do
    ~H"""
    <div class="noora-line-divider">
      <div data-part="line"></div>
      <span :if={@text} data-part="text">{@text}</span>
      <div data-part="line"></div>
    </div>
    """
  end
end
