defmodule Tuist.Docs.Doc do
  @moduledoc false
  @enforce_keys [:title, :slug, :body]
  defstruct [:title, :description, :title_template, :slug, :body]

  def build(filename, attrs, body) do
    if String.contains?(filename, "[") do
      :skip
    else
      slug = derive_slug(filename)

      struct!(__MODULE__,
        title: attrs["title"],
        description: attrs["description"],
        title_template: attrs["titleTemplate"],
        slug: slug,
        body: body
      )
    end
  end

  defp derive_slug(filename) do
    relative =
      case String.split(filename, "/docs/en/") do
        [_, rest] -> rest
        _ -> filename
      end

    slug =
      relative
      |> String.replace(~r/\.md$/, "")
      |> String.replace(~r/\/index$/, "")

    "/docs/" <> slug
  end
end
