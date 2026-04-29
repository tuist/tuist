defmodule Tuist.Marketing.Changelog do
  @moduledoc ~S"""
  This module loads the changelog entries to be used in the changelog section of the marketing website.
  The content is included in the compiled Erlang binary.
  """

  alias Tuist.Marketing.Changelog.Entry
  alias Tuist.Marketing.Changelog.EntryParser
  alias Tuist.Marketing.MDExConverter

  if Mix.env() == :dev do
    @entries_opts [
      build: Entry,
      from: Path.expand("../../../priv/marketing/changelog/**/*.md", __DIR__),
      parser: EntryParser,
      highlighters: [],
      html_converter: MDExConverter
    ]

    def get_entries do
      __MODULE__
      |> Tuist.Marketing.RuntimeStore.entries(@entries_opts)
      |> Enum.reverse()
    end

    def get_categories do
      get_entries() |> Enum.map(& &1.category) |> Enum.uniq()
    end
  else
    use NimblePublisher,
      build: Entry,
      from: Application.app_dir(:tuist, "priv/marketing/changelog/**/*.md"),
      as: :entries,
      parser: EntryParser,
      highlighters: [],
      html_converter: MDExConverter

    @entries Enum.reverse(@entries)
    @categories @entries |> Enum.map(& &1.category) |> Enum.uniq()

    def get_entries, do: @entries
    def get_categories, do: @categories
  end

  def get_entry_by_id(id), do: Enum.find(get_entries(), &(&1.id == id))
end
