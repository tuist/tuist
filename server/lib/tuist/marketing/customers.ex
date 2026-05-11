defmodule Tuist.Marketing.Customers do
  @moduledoc ~S"""
  This module loads the case studies to be used in the case studies section of the marketing website.
  The content is included in the compiled Erlang binary.
  """
  use Tuist.Marketing.NimblePublisher.Content,
    build: Tuist.Marketing.Customers.CaseStudy,
    dev_from: Path.expand("../../../priv/marketing/case_studies/*.md", __DIR__),
    prod_from: Application.app_dir(:tuist, "priv/marketing/case_studies/*.md"),
    as: :case_studies,
    parser: Tuist.Marketing.Customers.CaseParser,
    highlighters: [],
    html_converter: Tuist.Marketing.MDExConverter

  alias Tuist.Marketing.Customers.CaseStudy

  defp case_studies do
    Enum.sort_by(content_entries(), & &1.date, {:desc, Date})
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
