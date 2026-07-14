defmodule Tuist.Docs.NimblePublisher.Cache do
  @moduledoc false

  alias Tuist.ContentCache
  alias Tuist.Docs.Loader

  def start_link(_opts) do
    ContentCache.start_link(name: __MODULE__)
  end

  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}
  end

  def pages do
    current().pages
  end

  def slugs do
    ContentCache.get(__MODULE__, :slugs, &Loader.load_slugs!/0)
  end

  def get_page(slug) do
    ContentCache.get(__MODULE__, {:page, slug}, fn -> Loader.load_page!(slug) end)
  end

  def reload do
    ContentCache.reload(__MODULE__)
  end

  defp current do
    ContentCache.get(__MODULE__, :docs, &load/0)
  end

  defp load do
    {pages, _source_paths} = Loader.load_pages!()
    pages_by_slug = Map.new(pages, &{&1.slug, &1})

    %{
      pages: pages,
      pages_by_slug: pages_by_slug,
      slugs: pages_by_slug |> Map.keys() |> Enum.sort()
    }
  end
end
