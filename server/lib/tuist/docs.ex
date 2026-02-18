defmodule Tuist.Docs do
  @moduledoc false
  use NimblePublisher,
    build: Tuist.Docs.Doc,
    from: Application.app_dir(:tuist, "priv/docs/en/**/*.md"),
    as: :docs,
    parser: Tuist.Docs.DocParser,
    highlighters: []

  @docs @docs
        |> Enum.reject(&(&1 == :skip))
        |> Enum.group_by(& &1.slug)
        |> Enum.map(fn {_slug, docs} ->
          Enum.find(docs, List.first(docs), fn doc ->
            String.ends_with?(doc.slug, "index") == false
          end)
        end)

  def get_docs, do: @docs

  def get_doc_by_slug(slug) do
    Enum.find(@docs, fn doc -> doc.slug == slug end)
  end
end
