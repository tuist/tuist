defmodule Tuist.Marketing.Newsletter do
  @moduledoc ~S"""
  This module provides an interface to read the content for the newsletter.
  """
  use NimblePublisher,
    build: Tuist.Marketing.Newsletter.Issue,
    from: Application.app_dir(:tuist, "priv/marketing/newsletter/issues/*.yml"),
    as: :issues,
    parser: Tuist.Marketing.Newsletter.IssueParser,
    highlighters: []

  def issues, do: @issues

  def description do
    "A newsletter crafted by the Tuist team, featuring curated reads from the Swift ecosystem and beyond. Each edition highlights the most insightful articles, tutorials, and ideas shaping the Swift community, delivered straight to your inbox."
  end
end
