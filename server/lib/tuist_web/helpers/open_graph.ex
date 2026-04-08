defmodule TuistWeb.Helpers.OpenGraph do
  @moduledoc """
  Helper functions for generating OpenGraph meta tag assigns for LiveView pages.
  """

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
  Builds a locale-specific OG image path for marketing pages. For English,
  returns the path as-is. For other locales, inserts the locale before the
  filename.

  ## Examples

      marketing_og_image_path("/marketing/images/og/generated/about.jpg")
      # English: "/marketing/images/og/generated/about.jpg"
      # Korean:  "/marketing/images/og/generated/ko/about.jpg"

  """
  def marketing_og_image_path(path) do
    locale = Gettext.get_locale(TuistWeb.Gettext)

    if locale == "en" do
      path
    else
      dirname = Path.dirname(path)
      basename = Path.basename(path)
      Path.join([dirname, locale, basename])
    end
  end
end
