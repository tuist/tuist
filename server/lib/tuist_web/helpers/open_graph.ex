defmodule TuistWeb.Helpers.OpenGraph do
  @moduledoc """
  Helper functions for generating Open Graph meta tag assigns for LiveView pages.
  """

  alias Tuist.Marketing.OpenGraphImage

  @doc """
  Returns OpenGraph assigns for dashboard pages.

  Returns assigns for `head_image` and `head_twitter_card`. The images are
  generic and don't contain any project-specific information, so they are
  shown for all projects regardless of visibility.

  ## Parameters

    * `image_name` - The name of the image file (without extension or path prefix)

  ## Examples

      og_image_assigns("overview")
      og_image_assigns("build-runs")

  """
  def og_image_assigns(image_name) do
    [
      head_image: Tuist.Environment.app_url(path: "/images/open-graph/dashboard/#{image_name}.jpg"),
      head_twitter_card: "summary_large_image"
    ]
  end

  @doc """
  Builds a locale-specific, content-addressed Open Graph image path for
  marketing pages. For other supported locales, it inserts the locale before
  the filename. It falls back to English for unknown locales.

  ## Examples

      marketing_og_image_path("/marketing/images/og/generated/about.jpg")
      # English:  "/marketing/images/og/generated/about-<content-key>.jpg"
      # Korean:   "/marketing/images/og/generated/ko/about-<content-key>.jpg"
      # Spanish:  "/marketing/images/og/generated/es/about-<content-key>.jpg"

  """
  @og_image_locales TuistWeb.Marketing.Localization.all_locales()

  def marketing_og_image_path(path, opts \\ []) do
    locale = Gettext.get_locale(TuistWeb.Gettext)
    localize? = Keyword.get(opts, :localize, true)

    localized_path =
      if not localize? or locale == "en" or locale not in @og_image_locales do
        path
      else
        dirname = Path.dirname(path)
        basename = Path.basename(path)
        Path.join([dirname, locale, basename])
      end

    OpenGraphImage.versioned_path(localized_path)
  end
end
