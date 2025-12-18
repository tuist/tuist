defmodule Tuist.Marketing.CaseStudies.Case do
  @moduledoc false
  @enforce_keys [:title, :date, :company, :url, :founded_date, :onboarded_date, :body, :slug]
  defstruct [
    :title,
    :date,
    :company,
    :url,
    :founded_date,
    :onboarded_date,
    :body,
    :slug
  ]

  def build(filename, attrs, body) do
    title = String.trim_trailing(attrs["title"], ".")
    slug = "/case-studies/#{Path.basename(filename, ".md")}"

    struct!(__MODULE__,
      title: title,
      date: Date.from_iso8601!(attrs["date"]),
      company: attrs["company"],
      url: attrs["url"],
      founded_date: attrs["founded_date"],
      onboarded_date: Date.from_iso8601!(attrs["onboarded_date"]),
      body: body,
      slug: slug
    )
  end
end
