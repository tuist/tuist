defmodule Tuist.Docs.FileWatcher do
  @moduledoc false

  use GenServer

  alias Tuist.Docs.RuntimeStore

  @docs_root Path.expand("../../../priv/docs", __DIR__)
  @examples_root Path.expand("../../../../examples/xcode", __DIR__)
  @reload_delay_ms 100

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, watcher_pid} = FileSystem.start_link(dirs: Enum.filter([@docs_root, @examples_root], &File.dir?/1))
    FileSystem.subscribe(watcher_pid)

    {:ok, %{reload_timer: nil, watcher_pid: watcher_pid}}
  end

  @impl true
  def handle_info({:file_event, _watcher_pid, {path, _events}}, state) do
    if String.ends_with?(path, ".md") do
      {:noreply, schedule_reload(state)}
    else
      {:noreply, state}
    end
  end

  def handle_info({:file_event, _watcher_pid, :stop}, state) do
    {:noreply, state}
  end

  def handle_info(:reload, state) do
    RuntimeStore.reload()
    {:noreply, %{state | reload_timer: nil}}
  end

  defp schedule_reload(%{reload_timer: nil} = state) do
    %{state | reload_timer: Process.send_after(self(), :reload, @reload_delay_ms)}
  end

  defp schedule_reload(state), do: state
end
