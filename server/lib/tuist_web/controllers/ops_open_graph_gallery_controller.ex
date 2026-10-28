defmodule TuistWeb.OpsOpenGraphGalleryController do
  @moduledoc """
  Dev-only gallery of every Open Graph image the site can serve, static
  and generated, on one page (`/ops/og-gallery`): the designed marketing
  and dashboard cards, the other static images, and one sample render per
  runtime template. A place to check the whole set at once while the
  cards are being redesigned; it is mounted only in development.
  """
  use TuistWeb, :controller

  alias Tuist.Marketing.Blog.CoverArtwork, as: BlogCoverArtwork
  alias Tuist.Marketing.Customers.CoverArtwork
  alias TuistWeb.Helpers.OpenGraph

  def index(conn, _params) do
    priv = Application.app_dir(:tuist, "priv")

    sections = [
      %{
        title: "Marketing cards (static, SocialCards)",
        note:
          "priv/static/marketing/images/og/<page>.png — used by the page of the same name once it is on the new design.",
        images: static_images(priv, "static/marketing/images/og", "*.png", "/marketing/images/og")
      },
      %{
        title: "Dashboard cards (static, OpenGraph.og_image_assigns/1)",
        note: "priv/static/images/open-graph/dashboard/<page>.png",
        images: static_images(priv, "static/images/open-graph/dashboard", "*.png", "/images/open-graph/dashboard")
      },
      %{
        title: "Other static images",
        note: "Default card, organization logos, the text-card template.",
        images: [
          %{label: "open-graph/card.jpeg — default card (dashboard, error pages)", src: "/images/open-graph/card.jpeg"},
          %{
            label: "open-graph/squared.png — organization logo (structured data, API spec)",
            src: "/images/open-graph/squared.png"
          },
          %{label: "open-graph/api-docs-card.jpeg — API docs", src: "/images/open-graph/api-docs-card.jpeg"},
          %{
            label: "og_template.png — title-on-template background (blog/changelog/newsletter items)",
            src: "/images/og_template.png"
          },
          %{
            label: "og_marketing_template.png — title card background (pages without a designed card)",
            src: "/images/og_marketing_template.png"
          },
          %{label: "tuist_social.jpeg — organization logo (structured data)", src: "/images/tuist_social.jpeg"},
          %{label: "docs/images/logo.webp — logo in old docs pages", src: "/docs/images/logo.webp"}
        ]
      },
      %{
        title: "Generated cards (one sample per template)",
        note: "Rendered on request by the Open Graph image templates; the sample titles are placeholders.",
        images: generated_samples()
      }
    ]

    conn
    |> put_root_layout(false)
    |> put_layout(false)
    |> render(:index, sections: sections)
  end

  defp static_images(priv, dir, glob, url_prefix) do
    priv
    |> Path.join(dir)
    |> Path.join(glob)
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map(fn path ->
      name = Path.basename(path)
      %{label: name, src: "#{url_prefix}/#{name}"}
    end)
  end

  defp generated_samples do
    [
      {"marketing — title centered on og_marketing_template.png (pages without a designed card)",
       OpenGraph.image_path(:marketing, title: "Sample page")},
      {"marketing_text — title on og_template.png (blog posts without a cover, changelog entries, newsletter issues)",
       OpenGraph.image_path(:marketing_text, title: "A sample title that wraps onto a second line")},
      {"docs — per-page docs card",
       OpenGraph.image_path(:docs, title: "Install Tuist", description: "Sample description", category: "Guides")}
    ]
    |> Kernel.++(case_study_sample())
    |> Kernel.++(blog_cover_sample())
    |> Enum.map(fn {label, path} -> %{label: label, src: path} end)
  end

  defp case_study_sample do
    if CoverArtwork.available?("monzo"),
      do: [
        {"marketing_case_study — cover artwork card (monzo)", OpenGraph.image_path(:marketing_case_study, slug: "monzo")}
      ],
      else: []
  end

  defp blog_cover_sample do
    if BlogCoverArtwork.available?("swifterpm"),
      do: [
        {"marketing_blog_cover — blog cover card (swifterpm)",
         OpenGraph.image_path(:marketing_blog_cover, slug: "swifterpm")}
      ],
      else: []
  end
end
