defmodule Tuist.Docs.Content do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      if Mix.env() == :dev do
        alias Tuist.Docs.NimblePublisher.Cache

        defp static_pages, do: Cache.pages()
        defp static_page(slug), do: Cache.get_page(slug)
        defp static_slugs, do: Cache.slugs()
      else
        alias Tuist.Docs.Loader

        {pages, source_paths} = Loader.load_pages!()

        for source_path <- source_paths do
          @external_resource source_path
        end

        @pages pages
        @pages_by_slug Map.new(@pages, &{&1.slug, &1})
        @slugs @pages_by_slug |> Map.keys() |> Enum.sort()

        defp static_pages, do: @pages
        defp static_page(slug), do: Map.get(@pages_by_slug, slug)
        defp static_slugs, do: @slugs
      end
    end
  end
end
