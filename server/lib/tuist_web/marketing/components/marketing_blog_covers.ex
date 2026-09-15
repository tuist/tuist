defmodule TuistWeb.Marketing.MarketingBlogCovers do
  @moduledoc """
  Renders the SVG cover artwork on the redesigned blog index cards, the
  blog post hero and the post page's "Read next" cards.

  The artwork comes from `Tuist.Marketing.Blog.CoverArtwork`, read from
  `priv/marketing/blog/covers/<basename>.svg` — the same file that feeds
  the post's Open Graph image. Paints carry data-fill / data-stroke
  attributes (theme-following CSS, see marketing_new.css) so one SVG
  serves both themes; posts without a cover file keep their raster image.

  The blog index also lists the customer case studies; those cards show
  the same generated artwork as the customers page
  (`MarketingCustomerCovers`).
  """
  use TuistWeb, :html

  alias Tuist.Marketing.Blog.CoverArtwork
  alias TuistWeb.Marketing.MarketingCustomerCovers

  @doc """
  Whether `post` (or a `{:post, post}` / `{:case_study, case_study}` blog
  index entry) has cover artwork.
  """
  def cover?({:post, post}), do: cover?(post)
  def cover?({:case_study, case_study}), do: MarketingCustomerCovers.cover?(case_study)
  def cover?(%{slug: _slug} = post), do: post |> CoverArtwork.basename() |> CoverArtwork.available?()
  def cover?(_entry), do: false

  @doc """
  The cover artwork for `post` as an inline SVG. Decorative — the card or
  page title names the post — so it is hidden from assistive technology.
  """
  attr :post, :any, required: true

  def cover(%{post: {:post, post}} = assigns), do: cover(assign(assigns, :post, post))

  def cover(%{post: {:case_study, case_study}} = assigns) do
    assigns = assign(assigns, :case_study, case_study)

    ~H"<MarketingCustomerCovers.cover case_study={@case_study} />"
  end

  def cover(assigns) do
    assigns = assign(assigns, :svg, assigns.post |> CoverArtwork.basename() |> CoverArtwork.svg(:page))

    ~H"{raw(@svg)}"
  end
end
