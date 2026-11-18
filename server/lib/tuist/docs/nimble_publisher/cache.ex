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

  # Loads only the requested locale through the per-page cache. Building every
  # locale at once renders thousands of translated pages in a single load.
  def pages(locale) do
    slugs()
    |> Enum.filter(&(&1 == "/#{locale}" or String.starts_with?(&1, "/#{locale}/")))
    |> Enum.map(&get_page/1)
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
