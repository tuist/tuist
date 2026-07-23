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
    ContentCache.get(__MODULE__, :pages, fn ->
      {pages, _source_paths} = Loader.load_pages!()
      pages
    end)
  end

  def slugs do
    page_sources()
    |> Map.keys()
    |> Enum.sort()
  end

  def get_page(slug) do
    case Map.fetch(page_sources(), slug) do
      {:ok, page_source} ->
        ContentCache.get(__MODULE__, {:page, slug}, fn -> Loader.load_page_source!(page_source) end)

      :error ->
        nil
    end
  end

  def reload do
    ContentCache.reload(__MODULE__)
  end

  defp page_sources do
    ContentCache.get(__MODULE__, :page_sources, &Loader.load_page_sources!/0)
  end
end
