defmodule Tuist.ContentCache do
  @moduledoc false

  use GenServer

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  def get(name, key, loader) when is_atom(name) and is_function(loader, 0) do
    if pid = Process.whereis(name) do
      GenServer.call(pid, {:get, key, loader}, 60_000)
    else
      loader.()
    end
  end

  def reload(name) when is_atom(name) do
    if pid = Process.whereis(name) do
      GenServer.cast(pid, :reload)
    end
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call({:get, key, loader}, _from, state) do
    case state do
      %{^key => %{value: value}} ->
        {:reply, value, state}

      _ ->
        value = loader.()
        {:reply, value, Map.put(state, key, %{loader: loader, value: value})}
    end
  end

  @impl true
  def handle_cast(:reload, state) do
    state =
      Map.new(state, fn {key, %{loader: loader}} ->
        {key, %{loader: loader, value: loader.()}}
      end)

    {:noreply, state}
  end
end
