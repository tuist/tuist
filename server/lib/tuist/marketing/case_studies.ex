defmodule Tuist.Marketing.CaseStudies do
  @moduledoc ~S"""
  This module loads the case studies to be used in the case studies section of the marketing website.
  The content is included in the compiled Erlang binary.
  """
  use NimblePublisher,
    build: Tuist.Marketing.CaseStudies.CaseStudy,
    from: Application.app_dir(:tuist, "priv/marketing/case_studies/*.md"),
    as: :cases,
    parser: Tuist.Marketing.CaseStudies.CaseParser,
    highlighters: [],
    earmark_options: [
      smartypants: false,
      postprocessor: &Tuist.Earmark.ASTProcessor.process/1
    ]

  @cases Enum.sort_by(@cases, & &1.date, {:desc, Date})

  def get_cases, do: @cases
end
