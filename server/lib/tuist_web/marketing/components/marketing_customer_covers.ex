defmodule TuistWeb.Marketing.MarketingCustomerCovers do
  @moduledoc """
  Renders the generated SVG cover artwork on the redesigned customer
  case-study cards and the case-study hero.

  The artwork itself (dither-dot field + centered company logo) comes from
  `Tuist.Marketing.Customers.CoverArtwork`, generated from a logo file at
  `priv/marketing/customers/logos/<basename>.svg` — the same source that
  feeds the case study's Open Graph image. Dots carry data-fill attributes
  (theme-following CSS fills, see marketing.css) and logos use
  currentColor for their neutral parts, so one SVG serves both themes.
  """
  use TuistWeb, :html

  alias Tuist.Marketing.Customers.CoverArtwork
  alias TuistWeb.Helpers.OpenGraph

  @doc """
  Whether `case_study` has cover artwork. Cards fall back to the case
  study's OG image when it doesn't.
  """
  def cover?(case_study), do: CoverArtwork.available?(basename(case_study))

  @doc """
  The cover artwork for `case_study` as an inline SVG. Decorative — the
  card title names the company — so it is hidden from assistive
  technology.
  """
  attr :case_study, :map, required: true

  def cover(assigns) do
    assigns = assign(assigns, :svg, assigns.case_study |> basename() |> CoverArtwork.svg(:page))

    ~H"{raw(@svg)}"
  end

  @doc """
  The path of `case_study`'s social image: a path its front matter names,
  else the generated cover-artwork card, else the title-on-template card
  every page without artwork gets. Also the raster the legacy pages show
  where they have no inline artwork.
  """
  def og_image_path(case_study) do
    cond do
      case_study.og_image_path -> case_study.og_image_path
      cover?(case_study) -> OpenGraph.image_path(:marketing_case_study, slug: basename(case_study))
      true -> OpenGraph.image_path(:marketing_text, title: case_study.title)
    end
  end

  defp basename(case_study), do: Path.basename(case_study.slug)
end
