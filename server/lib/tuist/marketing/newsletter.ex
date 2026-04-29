defmodule Tuist.Marketing.Newsletter do
  @moduledoc ~S"""
  This module provides an interface to read the content for the newsletter.
  """

  alias Tuist.Marketing.Newsletter.Issue
  alias Tuist.Marketing.Newsletter.IssueParser

  if Mix.env() == :dev do
    @issues_opts [
      build: Issue,
      from: Path.expand("../../../priv/marketing/newsletter/issues/*.yml", __DIR__),
      parser: IssueParser,
      highlighters: []
    ]

    def issues do
      Tuist.Marketing.RuntimeStore.entries(__MODULE__, @issues_opts)
    end
  else
    use NimblePublisher,
      build: Issue,
      from: Application.app_dir(:tuist, "priv/marketing/newsletter/issues/*.yml"),
      as: :issues,
      parser: IssueParser,
      highlighters: []

    def issues, do: @issues
  end

  def description do
    "A newsletter crafted by the Tuist team, featuring curated reads from the Swift ecosystem and beyond. Each edition highlights the most insightful articles, tutorials, and ideas shaping the Swift community, delivered straight to your inbox."
  end
end
