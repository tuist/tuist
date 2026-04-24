defmodule Tuist.Marketing.Customers do
  @moduledoc ~S"""
  This module loads the case studies to be used in the case studies section of the marketing website.
  The content is included in the compiled Erlang binary.
  """
  alias Tuist.Marketing.Customers.CaseStudy

  use NimblePublisher,
    build: Tuist.Marketing.Customers.CaseStudy,
    from: Application.app_dir(:tuist, "priv/marketing/case_studies/*.md"),
    as: :case_studies,
    parser: Tuist.Marketing.Customers.CaseParser,
    highlighters: [],
    html_converter: Tuist.Marketing.MDExConverter

  @case_studies Enum.sort_by(@case_studies, & &1.date, {:desc, Date})

  def get_case_studies(locale \\ "en") do
    Enum.map(@case_studies, &CaseStudy.localize(&1, locale))
  end

  def get_case_study(slug, locale \\ "en") do
    slug = String.trim_trailing(slug, "/")

    @case_studies
    |> Enum.find(&(&1.slug == slug))
    |> case do
      nil -> nil
      case_study -> CaseStudy.localize(case_study, locale)
    end
  end
end
