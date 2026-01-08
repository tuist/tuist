defmodule Tuist.Marketing.Customers do
  @moduledoc ~S"""
  This module loads the case studies to be used in the case studies section of the marketing website.
  The content is included in the compiled Erlang binary.
  """
  use NimblePublisher,
    build: Tuist.Marketing.Customers.CaseStudy,
    from: Application.app_dir(:tuist, "priv/marketing/case_studies/*.md"),
    as: :case_studies,
    parser: Tuist.Marketing.Customers.CaseParser,
    highlighters: [],
    earmark_options: [
      smartypants: false,
      postprocessor: &Tuist.Earmark.ASTProcessor.process/1
    ]

  @case_studies Enum.sort_by(@case_studies, & &1.date, {:desc, Date})

  def get_case_studies, do: @case_studies
end
