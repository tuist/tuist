defmodule Tuist.Marketing.CaseStudies.Case do
  @enforce_keys [:title, :date, :name, :url, :founded, :onboarded, :body, :slug]
  defstruct [
    :title,
    :date,
    :name,
    :url,
    :founded,
    :onboarded,
    :body,
    :slug
  ]

  def build(filename, attrs, body) do
    title = String.trim_trailing(attrs["title"], ".")
    slug = "/case-studies/#{Path.basename(filename, ".md")}"

    struct!(__MODULE__,
      title: title,
      date: Date.from_iso8601!(attrs["date"]),
      name: attrs["name"],
      url: attrs["url"],
      founded: attrs["founded"],
      onboarded: Date.from_iso8601!(attrs["onboarded"]),
      body: body,
      slug: slug
    )
  end
end
