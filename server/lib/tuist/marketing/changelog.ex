defmodule Tuist.Marketing.Changelog do
  @moduledoc ~S"""
  This module loads the changelog entries to be used in the changelog section of the marketing website.
  The content is included in the compiled Erlang binary.
  """

  use Tuist.Marketing.NimblePublisher.Content,
    build: Tuist.Marketing.Changelog.Entry,
    dev_from: Path.expand("../../../priv/marketing/changelog/**/*.md", __DIR__),
    prod_from: Application.app_dir(:tuist, "priv/marketing/changelog/**/*.md"),
    as: :entries,
    parser: Tuist.Marketing.Changelog.EntryParser,
    highlighters: [],
    html_converter: Tuist.Marketing.MDExConverter

  def get_entries do
    Enum.reverse(content_entries())
  end

  def get_categories do
    get_entries() |> Enum.map(& &1.category) |> Enum.uniq()
  end

  def get_entry_by_id(id), do: Enum.find(get_entries(), &(&1.id == id))
end
