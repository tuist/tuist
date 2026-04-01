defmodule TuistWeb.Docs.MarkdownComponents do
  @moduledoc """
  Phoenix components designed for use directly inside documentation
  markdown files. These replace the VitePress/Vue custom elements
  (HomeCards, Badge, etc.) with native Phoenix LiveView components
  that work through HEEx compilation of markdown.
  """
  use Phoenix.Component
  use Noora

  alias Tuist.Docs.Paths

  attr :locale, :string, default: "en"
  slot :inner_block, required: true

  def home_cards(assigns) do
    ~H"""
    <div data-part="feature-cards">
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :title, :string, required: true
  attr :details, :string, required: true
  attr :link, :string, required: true
  attr :locale, :string, default: "en"

  def home_card(assigns) do
    href =
      if String.starts_with?(assigns.link, "http") do
        assigns.link
      else
        Paths.public_path(assigns.locale, assigns.link)
      end

    assigns = assign(assigns, :href, href)

    ~H"""
    <a href={@href} data-part="feature-card">
      <div data-part="feature-card-image">
        <span data-part="feature-card-title">{@title}</span>
      </div>
      <div data-part="feature-card-body">
        <p>{@details}</p>
      </div>
    </a>
    """
  end
end
