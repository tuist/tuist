defmodule Tuist.Docs.RuntimeStore do
  @moduledoc false

  use GenServer

  alias Tuist.Docs.Loader

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def pages do
    current().pages
  end

  def slugs do
    current().slugs
  end

  def get_page(slug) do
    current().pages_by_slug[slug]
  end

  def reload do
    if pid = Process.whereis(__MODULE__) do
      GenServer.cast(pid, :reload)
    end
  end

  @impl true
  def init(_opts) do
    {:ok, load()}
  end

  @impl true
  def handle_call(:current, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast(:reload, _state) do
    {:noreply, load()}
  end

  defp current do
    if pid = Process.whereis(__MODULE__) do
      GenServer.call(pid, :current, 60_000)
    else
      load()
    end
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
