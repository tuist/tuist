defmodule Tuist.Marketing.Changelog do
  @moduledoc ~S"""
  This module loads the changelog entries to be used in the changelog section of the marketing website.
  The content is included in the compiled Erlang binary.
  """
  alias Tuist.Marketing.Changelog.Entry
  alias Tuist.Marketing.Changelog.EntryParser
  alias Tuist.Earmark.ASTProcessor

  use NimblePublisher,
    build: Entry,
    from: Application.app_dir(:tuist, "priv/marketing/changelog/**/*.md"),
    as: :entries,
    parser: EntryParser,
    highlighters: [],
    earmark_options: [
      smartypants: false,
      postprocessor: &ASTProcessor.process/1
    ]

  @entries @entries |> Enum.reverse()
  @categories @entries |> Enum.map(& &1.category) |> Enum.uniq()

  def get_entries, do: @entries
  def get_categories, do: @categories
end
