defmodule Tuist.Marketing.Changelog do
  @moduledoc ~S"""
  This module loads the changelog entries to be used in the changelog section of the marketing website.
  The content is included in the compiled Erlang binary.
  """
  use NimblePublisher,
    build: Tuist.Marketing.Changelog.Entry,
    from: Application.app_dir(:tuist, "priv/marketing/changelog/**/*.md"),
    as: :entries,
    parser: Tuist.Marketing.Changelog.EntryParser,
    highlighters: [],
    earmark_options: [
      smartypants: false,
      postprocessor: &Tuist.Earmark.ASTProcessor.process/1
    ]

  @entries Enum.reverse(@entries)
  @categories @entries |> Enum.map(& &1.category) |> Enum.uniq()

  def get_entries, do: @entries
  def get_categories, do: @categories
end
