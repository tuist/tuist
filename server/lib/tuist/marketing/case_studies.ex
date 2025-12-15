defmodule Tuist.Marketing.CaseStudies do
  @moduledoc ~S"""
  This module loads the blog posts and authors to be used in the blog section of the marketing website.
  The content is included in the compiled Erlang binary.
  """
  use NimblePublisher,
    build: Tuist.Marketing.CaseStudies.Case,
    from: Application.app_dir(:tuist, "priv/marketing/case_studies/*.md"),
    as: :cases,
    parser: Tuist.Marketing.CaseStudies.CaseParser,
    highlighters: [],
    earmark_options: [
      smartypants: false,
      postprocessor: &Tuist.Earmark.ASTProcessor.process/1
    ]

  def cases, do: @cases
end
