defmodule TuistEx.Lock do
  @moduledoc false

  @timeout_ms 35_000
  @stale_seconds 10
  @heartbeat_ms 2_000

  def with_lock(path, action) do
    File.mkdir_p!(Path.dirname(path))
    deadline = System.monotonic_time(:millisecond) + @timeout_ms
    acquire(path, action, deadline)
  end

  defp acquire(path, action, deadline) do
    owner = Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)

    case File.open(path, [:write, :exclusive]) do
      {:ok, file} ->
        :ok = IO.binwrite(file, owner)
        File.close(file)
        run_owned(path, owner, action)

      {:error, :eexist} ->
        reap_stale(path)

        if System.monotonic_time(:millisecond) >= deadline do
          {:error, "Timed out waiting for the Tuist authentication lock"}
        else
          Process.sleep(50)
          acquire(path, action, deadline)
        end

      {:error, reason} ->
        {:error, "Could not acquire the Tuist authentication lock: #{inspect(reason)}"}
    end
  end

  defp run_owned(path, owner, action) do
    caller = self()
    {:ok, heartbeat} = Task.start(fn -> heartbeat(path, owner, Process.monitor(caller)) end)

    try do
      action.()
    after
      monitor = Process.monitor(heartbeat)
      Process.exit(heartbeat, :kill)

      receive do
        {:DOWN, ^monitor, :process, ^heartbeat, _} -> :ok
      end

      remove_if_owned(path, owner)
    end
  end

  defp heartbeat(path, owner, caller_monitor) do
    receive do
      {:DOWN, ^caller_monitor, :process, _, _} ->
        :ok
    after
      @heartbeat_ms ->
        if File.read(path) == {:ok, owner} and File.exists?(path) do
          File.touch(path)
          heartbeat(path, owner, caller_monitor)
        end
    end
  end

  defp reap_stale(path) do
    guard_path = path <> ".reap"

    case File.open(guard_path, [:write, :exclusive]) do
      {:ok, guard} ->
        File.close(guard)

        try do
          if stale?(path), do: File.rm(path)
        after
          File.rm(guard_path)
        end

      {:error, :eexist} ->
        if stale?(guard_path), do: File.rm(guard_path)
        :ok

      {:error, _} ->
        :ok
    end
  end

  defp stale?(path) do
    case File.stat(path, time: :posix) do
      {:ok, %{mtime: modified}} -> modified < System.system_time(:second) - @stale_seconds
      _ -> false
    end
  end

  defp remove_if_owned(path, owner) do
    if File.read(path) == {:ok, owner}, do: File.rm(path)
  end
end
