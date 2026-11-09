defmodule Pulse.Test.CompactionPeer do
  @moduledoc false
  alias Pulse.Runtime.Task
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.CompactionOwnership
  alias Pulse.Storage.S3.CompactionTasks
  alias Pulse.Storage.S3.CompactionWorker

  # The peer controller is owned by the test supervisor, including on failure.
  def start_link({owner, config}) do
    name = :"compaction_#{Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)}"
    paths = Enum.flat_map(:code.get_path(), &[~c"-pa", &1])

    {:ok, peer, member} =
      :peer.start_link(%{
        name: name,
        host: ~c"127.0.0.1",
        longnames: true,
        connection: :standard_io,
        wait_boot: 30_000,
        args: [~c"+S", ~c"2", ~c"-setcookie", ~c"pulse_compaction_test"] ++ paths
      })

    try do
      for app <- [:pulse, :phoenix, :logger] do
        :ok = :peer.call(peer, Application, :put_all_env, [[{app, Application.get_all_env(app)}]])
      end

      :ok = :peer.call(peer, Application, :put_env, [:pulse, Pulse.Storage, [adapter: S3]])
      :ok = :peer.call(peer, Application, :put_env, [:pulse, S3, config])
      endpoint = Application.get_env(:pulse, PulseWeb.Endpoint) |> Keyword.put(:server, false)
      :ok = :peer.call(peer, Application, :put_env, [:pulse, PulseWeb.Endpoint, endpoint])
      {:ok, _} = :peer.call(peer, Application, :ensure_all_started, [:pulse], 30_000)
      send(owner, {:compaction_peer, peer, member})
      {:ok, peer}
    catch
      kind, reason ->
        :peer.stop(peer)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  def call(peer, module, function, args, timeout \\ 15_000) do
    :peer.call(peer, module, function, args, timeout)
  end

  def await_members(config, expected) do
    {ref, _} = :pg.monitor(Pulse.Runtime.name(CompactionOwnership.scope()), CompactionOwnership.group(config))

    try do
      await_view(config, Enum.sort(expected), ref, System.monotonic_time(:millisecond) + 5_000)
    after
      :pg.demonitor(Pulse.Runtime.name(CompactionOwnership.scope()), ref)
    end
  end

  defp await_view(config, expected, ref, deadline) do
    actual = config |> CompactionOwnership.members() |> Enum.sort()

    if actual == expected do
      :ok
    else
      receive do
        {^ref, _, _, _} -> await_view(config, expected, ref, deadline)
      after
        max(deadline - System.monotonic_time(:millisecond), 0) ->
          raise "membership did not converge: #{inspect(actual)} != #{inspect(expected)}"
      end
    end
  end

  def timeout(ms) do
    :sys.replace_state(CompactionWorker, &Map.put(&1, :compaction_timeout_ms, ms))
    :ok
  end

  def await_tasks do
    tasks = Task.Supervisor.children(CompactionTasks)

    for pid <- tasks do
      ref = Process.monitor(pid)

      receive do
        {:DOWN, ^ref, :process, ^pid, _} -> :ok
      after
        5_000 -> raise "timed-out native task has not terminated"
      end
    end

    _ = :sys.get_state(CompactionTasks)
    :ok
  end

  def pass do
    worker = Process.whereis(CompactionWorker)
    send(worker, :compact)
    _ = :sys.get_state(worker, 15_000)
    :ok
  end
end
