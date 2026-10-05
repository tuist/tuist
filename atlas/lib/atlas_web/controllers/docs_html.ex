defmodule AtlasWeb.DocsHTML do
  use AtlasWeb, :html
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias AtlasWeb.Docs.Markdown

  @overview_introduction "Atlas grew out of Tuist's need to maximize the value each employee could create. We engineered our operations around that goal: centralizing the company's context in one place, connecting it through database relationships, and giving agents and bots interfaces to query it and act on it. We built Atlas incrementally as our way of working evolved."

  @pages (for {slug, title, category, section, description} <- [
                {"", "Overview", "Overview", "Atlas",
                 "Built at Tuist to maximize value per employee: shared organizational context for people, agents, and bots."},
                {"mcps", "MCPs", "Guides", "Atlas", "Configure upstream MCP servers in Atlas."},
                {"self-hosting", "Self-hosting", "Guides", "Self-hosting",
                 "Deploy Atlas with Docker Compose or Helm on your own infrastructure."}
              ] do
            path = Path.expand("../../../priv/docs/#{if(slug == "", do: "overview", else: slug)}.md", __DIR__)
            @external_resource path
            body = File.read!(path)

            {html, headings} = Markdown.render_with_headings(body)

            %{
              slug: slug,
              title: title,
              category: category,
              section: section,
              description: description,
              introduction: @overview_introduction,
              html: html,
              markdown:
                "# #{if(slug == "", do: "Your operations, on auto-pilot", else: title)}\n\n" <>
                  if(slug == "", do: @overview_introduction <> "\n\n", else: "") <> body,
              headings: headings
            }
          end)

  def image_filename(slug), do: if(slug == "", do: "overview.png", else: slug <> ".png")

  def pages, do: @pages
  def page(slug), do: Enum.find(@pages, &(&1.slug == slug))

  attr :id, :string, required: true
  attr :slug, :string, required: true

  def page_copy(assigns) do
    ~H"""
    <div data-part="copy-dropdown">
      <.button_dropdown
        id={@id}
        label="Copy page"
        size="medium"
        on_select="docs-copy-selection"
        data-default-label="Copy page"
        data-copied-label="Copied"
        data-markdown-source-id="docs-page-markdown"
      >
        <:icon_left><.copy /></:icon_left>
        <.dropdown_item
          label="Copy page"
          description="Copy page as Markdown"
          value="copy-markdown"
          size="large"
        >
          <:left_icon><.copy /></:left_icon>
        </.dropdown_item>
        <.dropdown_item
          label="View as Markdown"
          description="View this page as plain text"
          value="view-markdown"
          href={if(@slug == "", do: ~p"/docs-markdown", else: ~p"/docs-markdown/#{@slug}")}
          size="large"
          target="_blank"
          rel="noopener noreferrer"
        >
          <:left_icon><.icon name="markdown" /></:left_icon>
          <:right_icon><.external_link /></:right_icon>
        </.dropdown_item>
      </.button_dropdown>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true

  def theme_toggle(assigns) do
    ~H"""
    <.button
      id={@id}
      variant="secondary"
      size="large"
      icon_only
      aria-label={@label}
      title={@label}
      data-part="theme-toggle"
    >
      <span data-part="theme-toggle-light-icon" aria-hidden="true"><.sun_high /></span>
      <span data-part="theme-toggle-dark-icon" aria-hidden="true"><.moon /></span>
    </.button>
    """
  end

  embed_templates "docs_html/*"
end
