defmodule TuistWeb.Marketing.MarketingCustomerCovers do
  @moduledoc """
  Renders the generated SVG cover artwork on the redesigned customer
  case-study cards and the case-study hero.

  The artwork itself (dither-dot field + centered company logo) comes from
  `Tuist.Marketing.Customers.CoverArtwork`, generated from a logo file at
  `priv/marketing/customers/logos/<basename>.svg` — the same source that
  feeds the case study's Open Graph image. Dots carry data-fill attributes
  (theme-following CSS fills, see marketing_new.css) and logos use
  currentColor for their neutral parts, so one SVG serves both themes.
  """
  use TuistWeb, :html

  alias Tuist.Marketing.Customers.CoverArtwork

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

  defp basename(case_study), do: Path.basename(case_study.slug)
end
