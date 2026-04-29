defmodule Tuist.Marketing.RuntimeStore do
  @moduledoc false

  use GenServer

  alias Tuist.Marketing.RuntimeLoader

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def entries(key, opts) do
    if pid = Process.whereis(__MODULE__) do
      GenServer.call(pid, {:entries, key, opts}, 60_000)
    else
      RuntimeLoader.build!(opts)
    end
  end

  def reload do
    if pid = Process.whereis(__MODULE__) do
      GenServer.cast(pid, :reload)
    end
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call({:entries, key, opts}, _from, state) do
    case state do
      %{^key => %{entries: entries}} ->
        {:reply, entries, state}

      _ ->
        entries = RuntimeLoader.build!(opts)
        {:reply, entries, Map.put(state, key, %{entries: entries, opts: opts})}
    end
  end

  @impl true
  def handle_cast(:reload, state) do
    state =
      Map.new(state, fn {key, %{opts: opts}} ->
        {key, %{entries: RuntimeLoader.build!(opts), opts: opts}}
      end)

    {:noreply, state}
  end
end
