defmodule Tuist.ContentFileWatcher do
  @moduledoc false

  use GenServer

  @reload_delay_ms 100

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    dirs = opts |> Keyword.fetch!(:dirs) |> Enum.filter(&File.dir?/1)
    extensions = Keyword.fetch!(opts, :extensions)
    cache = Keyword.fetch!(opts, :cache)

    {:ok, watcher_pid} = FileSystem.start_link(dirs: dirs)
    FileSystem.subscribe(watcher_pid)

    {:ok, %{cache: cache, extensions: extensions, reload_timer: nil, watcher_pid: watcher_pid}}
  end

  @impl true
  def handle_info({:file_event, _watcher_pid, {path, _events}}, state) do
    if String.ends_with?(path, state.extensions) do
      {:noreply, schedule_reload(state)}
    else
      {:noreply, state}
    end
  end

  def handle_info({:file_event, _watcher_pid, :stop}, state) do
    {:noreply, state}
  end

  def handle_info(:reload, state) do
    state.cache.reload()
    {:noreply, %{state | reload_timer: nil}}
  end

  defp schedule_reload(%{reload_timer: nil} = state) do
    %{state | reload_timer: Process.send_after(self(), :reload, @reload_delay_ms)}
  end

  defp schedule_reload(state), do: state
end
