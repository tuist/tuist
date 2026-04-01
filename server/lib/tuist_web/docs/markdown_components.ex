defmodule TuistWeb.Docs.MarkdownComponents do
  @moduledoc """
  Phoenix components for use directly inside documentation markdown
  files. Pages with `live: true` in frontmatter compile through HEEx,
  making these components available to authors.
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

  attr :href, :string, required: true
  attr :locale, :string, default: "en"
  slot :inner_block, required: true

  def localized_link(assigns) do
    href =
      if String.starts_with?(assigns.href, "http") do
        assigns.href
      else
        Paths.public_path(assigns.locale, assigns.href)
      end

    assigns = assign(assigns, :resolved_href, href)

    ~H"""
    <a href={@resolved_href}>{render_slot(@inner_block)}</a>
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
      <div data-part="image">
        <span data-part="title">{@title}</span>
      </div>
      <div data-part="body">
        <p>{@details}</p>
      </div>
    </a>
    """
  end
end
