defmodule TuistWeb.StructuredMarkup do
  @moduledoc """
  A set of utilities for generating structured markup data.
  - https://developers.google.com/search/docs/appearance/structured-data/intro-structured-data
  """

  def get_organization() do
    %{
      "@context" => "https://schema.org",
      "@type" => "Organization",
      "name" => "Tuist",
      "url" => Tuist.Environment.app_url(),
      "logo" => Tuist.Environment.app_url(path: "/images/tuist_social.jpeg"),
      "sameAs" => [
        "https://fosstodon.org/@tuist",
        "https://x.com/tuistio",
        "https://www.linkedin.com/company/tuistio"
      ]
    }
  end
end
