defmodule Tuist.Marketing.Customers do
  @moduledoc ~S"""
  This module loads the case studies to be used in the case studies section of the marketing website.
  The content is included in the compiled Erlang binary.
  """
  alias Tuist.Marketing.Customers.CaseParser
  alias Tuist.Marketing.Customers.CaseStudy
  alias Tuist.Marketing.MDExConverter

  if Mix.env() == :dev do
    @case_studies_opts [
      build: CaseStudy,
      from: Path.expand("../../../priv/marketing/case_studies/*.md", __DIR__),
      parser: CaseParser,
      highlighters: [],
      html_converter: MDExConverter
    ]

    defp case_studies do
      __MODULE__
      |> Tuist.Marketing.RuntimeStore.entries(@case_studies_opts)
      |> Enum.sort_by(& &1.date, {:desc, Date})
    end
  else
    use NimblePublisher,
      build: CaseStudy,
      from: Application.app_dir(:tuist, "priv/marketing/case_studies/*.md"),
      as: :case_studies,
      parser: CaseParser,
      highlighters: [],
      html_converter: MDExConverter

    @case_studies Enum.sort_by(@case_studies, & &1.date, {:desc, Date})

    defp case_studies, do: @case_studies
  end

  def get_case_studies(locale \\ "en") do
    Enum.map(case_studies(), &CaseStudy.localize(&1, locale))
  end

  def get_case_study(slug, locale \\ "en") do
    slug = String.trim_trailing(slug, "/")

    case_studies()
    |> Enum.find(&(&1.slug == slug))
    |> case do
      nil -> nil
      case_study -> CaseStudy.localize(case_study, locale)
    end
  end
end
