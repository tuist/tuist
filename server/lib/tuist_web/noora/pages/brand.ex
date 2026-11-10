defmodule TuistWeb.Noora.Pages.Brand do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Brand",
    description:
      "Resources for representing the Tuist brand clearly and cohesively. Tuist trademarks, logos, and other brand assets must not be modified or used for any purpose other than representing Tuist.",
    components: [{Noora.Brand, :tuist_wordmark}, {Noora.Brand, :tuist_logo}],
    guidelines: [
      "Keep the assets as provided. Don't recolor, stretch, rotate, or add effects to them.",
      "Use the wordmark whenever space allows, and the logo on its own only where the name doesn't fit.",
      "Don't use the assets in ways that could suggest an official partnership, sponsorship, or endorsement where one doesn't exist, or incorporate them into your own logo, product name, or brand identity.",
      "If you're unsure about a particular use, get in touch at contact@tuist.dev."
    ]

  @assets "/marketing/images/brand"

  @sections [
    %{
      id: "wordmark",
      title: "Wordmark",
      description:
        "Use the wordmark whenever space allows. The color version is preferred; use the monochrome version in layouts or contexts with a monochrome visual style.",
      name: "wordmark",
      label: "Tuist wordmark"
    },
    %{
      id: "logo",
      title: "Logo",
      description:
        "For tight layouts or logo-only grids, use the mark on its own, in color or monochrome. Keep the full wordmark where stronger brand recognition is needed.",
      name: "logo",
      label: "Tuist logo"
    }
  ]

  # Color on light, color on dark, then monochrome on light and on dark: the
  # same files and order as tuist.dev/brand.
  @variants [
    {"", "light", "in color on a light background"},
    {"-dark", "dark", "in color on a dark background"},
    {"-mono-light", "light", "in monochrome on a light background"},
    {"-mono-dark", "dark", "in monochrome on a dark background"}
  ]

  def content(assigns) do
    assigns =
      assign(assigns,
        sections:
          for section <- @sections do
            Map.put(
              section,
              :cells,
              for {suffix, surface, description} <- @variants do
                %{
                  src: "#{@assets}/tuist-#{section.name}#{suffix}.svg",
                  surface: surface,
                  alt: "#{section.label} #{description}"
                }
              end
            )
          end,
        zip: "#{@assets}/tuist-brand-assets.zip"
      )

    ~H"""
    <section data-part="section">
      <div>
        <.button href={@zip} label="Download brand assets" variant="secondary" {[download: true]}>
          <:icon_left><.download /></:icon_left>
        </.button>
      </div>
    </section>

    <section :for={section <- @sections} id={section.id} data-part="section">
      <h2><a href={"##{section.id}"}>{section.title}</a></h2>
      <p>{section.description}</p>
      <ul data-part="brand-grid">
        <li :for={cell <- section.cells} data-part="brand-cell" data-surface={cell.surface}>
          <img src={cell.src} alt={cell.alt} />
          <.ghost_button
            variant="secondary"
            data-part="download"
            href={cell.src}
            aria-label={"Download #{cell.alt}"}
            label="Download"
            {[download: true]}
          >
            <:icon_left><.download /></:icon_left>
          </.ghost_button>
        </li>
      </ul>
    </section>
    """
  end

  example "Wordmark component",
    description:
      "`<.tuist_wordmark>` draws the wordmark inline, so it needs no image request and follows the page's theme." do
    ~H"""
    <.tuist_wordmark />
    <.tuist_wordmark variant="mono" />
    """
  end

  example "Logo component", description: "`<.tuist_logo>` draws the mark on its own, for tight layouts." do
    ~H"""
    <.tuist_logo />
    <.tuist_logo variant="mono" />
    """
  end

  example "Sizes", description: "Set the height; the width follows the aspect ratio." do
    ~H"""
    <.tuist_wordmark height={24} />
    <.tuist_wordmark height={32} />
    <.tuist_wordmark height={48} />
    """
  end

  example "Fixed surfaces",
    description:
      "On a background that doesn't follow the page's theme, such as a dark hero, pin the colors with `surface`." do
    ~H"""
    <div style="padding: 24px; border-radius: 8px; background: #f7f7f7;">
      <.tuist_wordmark surface="light" />
    </div>
    <div style="padding: 24px; border-radius: 8px; background: #191a1b;">
      <.tuist_wordmark surface="dark" />
    </div>
    """
  end
end
