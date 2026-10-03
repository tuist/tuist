defmodule Atlas.GTM.Outreach.SearchSegments do
  @moduledoc false

  @version 1
  @titles [
    "head of mobile",
    "director of mobile engineering",
    "mobile engineering manager",
    "head of ios"
  ]
  @seniorities ~w(manager director head vp)
  @industry_keywords [
    "fintech",
    "banking",
    "payments",
    "e-commerce",
    "retail",
    "travel",
    "mobility",
    "gaming",
    "food delivery",
    "transportation"
  ]
  @excluded_title_terms ["mobile network", "mobile marketing", "hardware"]
  @excluded_industry_prefixes ["5415"]

  @segments [
    %{
      id: "mobile_mid_large",
      name: "Mobile leaders · 200–5,000 employees",
      version: @version,
      titles: @titles,
      seniorities: @seniorities,
      organization_num_employees_ranges: ["200,5000"],
      organization_keyword_tags: @industry_keywords,
      excluded_title_terms: @excluded_title_terms,
      excluded_industry_prefixes: @excluded_industry_prefixes,
      organization_limit: 100,
      people_limit: 50
    },
    %{
      id: "mobile_giants",
      name: "Mobile leaders · 5,000+ employees",
      version: @version,
      titles: @titles,
      seniorities: @seniorities,
      organization_num_employees_ranges: ["5000,1000000"],
      organization_keyword_tags: @industry_keywords,
      excluded_title_terms: @excluded_title_terms,
      excluded_industry_prefixes: @excluded_industry_prefixes,
      organization_limit: 100,
      people_limit: 50
    }
  ]

  def all, do: @segments

  def get(id) when is_binary(id), do: Enum.find(@segments, &(&1.id == id))
  def get(_id), do: nil

  def snapshot(segment) do
    segment
    |> Map.delete(:name)
    |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
  end

  def organization_exclusion(segment, organization) do
    naics_codes = organization.metadata["naics_codes"] || []

    if Enum.any?(naics_codes, &excluded_industry_code?(&1, segment.excluded_industry_prefixes)) do
      "consultancy_or_custom_software"
    end
  end

  def person_exclusion(segment, person) do
    title = person.title |> to_string() |> String.downcase()

    if Enum.any?(segment.excluded_title_terms, &String.contains?(title, &1)) do
      "irrelevant_mobile_title"
    end
  end

  defp excluded_industry_code?(code, prefixes) do
    code = to_string(code)
    Enum.any?(prefixes, &String.starts_with?(code, &1))
  end
end
