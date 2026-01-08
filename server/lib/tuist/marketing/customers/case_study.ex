defmodule Tuist.Marketing.Customers.CaseStudy do
  @moduledoc false
  @enforce_keys [
    :title,
    :date,
    :company,
    :url,
    :founded_date,
    :onboarded_date,
    :body,
    :slug,
    :og_image_path,
    :excerpt
  ]
  defstruct [
    :title,
    :date,
    :company,
    :url,
    :founded_date,
    :onboarded_date,
    :body,
    :slug,
    :og_image_path,
    :excerpt
  ]

  def build(filename, attrs, body) do
    title = String.trim_trailing(attrs["title"], ".")
    basename = Path.basename(filename, ".md")
    slug = "/customers/#{basename}"
    og_image_path = "/marketing/images/og/customers/#{basename}.jpg"

    struct!(__MODULE__,
      title: title,
      date: Date.from_iso8601!(attrs["date"]),
      company: attrs["company"],
      url: attrs["url"],
      founded_date: attrs["founded_date"],
      onboarded_date: Date.from_iso8601!(attrs["onboarded_date"]),
      body: body,
      slug: slug,
      og_image_path: og_image_path,
      excerpt: attrs["excerpt"]
    )
  end
end
