defmodule TuistWeb.Marketing.SocialCards do
  @moduledoc """
  The redesigned marketing pages' Open Graph images: one designed card per
  page, shipped as a static 1920x1080 PNG under
  `priv/static/marketing/images/og/`, instead of the runtime-rendered
  title cards the legacy pages use.

  A page with a card always uses it, on either design; pages without one
  keep their rendered title card. Per-item pages (blog posts, changelog
  entries, case studies, newsletter issues, docs pages) keep their
  generated images; the docs card is the docs landing page's only.
  """

  @cards ~w(home about brand download pricing blog cache tests compute previews customers changelog newsletter community docs imprint privacy openness security cookies terms longevity data-act-addendum data-processing-addendum service-level-addendum trademark-guidelines)

  @doc """
  Whether a designed card exists for `card`.
  """
  def available?(card) when is_binary(card), do: card in @cards
  def available?(_card), do: false

  @doc """
  The absolute URL of the designed card for `card`.
  """
  def image_url(card) do
    if !available?(card), do: raise(ArgumentError, "no social card named #{inspect(card)}")

    Tuist.Environment.app_url(path: "/marketing/images/og/#{card}.png", marketing: true)
  end

  @doc """
  The `head_image` URL for a page: its designed card when it has one,
  otherwise the URL of `fallback_path` (the rendered image's path, given as
  a zero-arity function so it is only signed when needed).
  """
  def head_image(card, fallback_path) when is_function(fallback_path, 0) do
    if available?(card) do
      image_url(card)
    else
      Tuist.Environment.app_url(path: fallback_path.(), marketing: true)
    end
  end
end
