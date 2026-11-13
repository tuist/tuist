defmodule Pulse.Health.StorageMonitorTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Health.StorageMonitor
  alias Pulse.Test.CompactionStore

  defp start_monitor(probe, opts \\ []) do
    name = :"monitor_#{System.unique_integer([:positive])}"
    opts = Keyword.merge([name: name, config: %{}, probe: probe, interval_ms: 10_000], opts)
    start_supervised!({StorageMonitor, opts})
    name
  end

  # `status/1` is a call, so it queues behind the `handle_continue` that
  # launches the first probe, but not behind the probe task itself. Poll the
  # monitor until the probe has reported.
  defp await_status(name, expected) do
    case StorageMonitor.status(name) do
      ^expected -> expected
      _ -> await_status(name, expected)
    end
  end

  test "is not ready before the first probe finishes" do
    test_pid = self()

    name =
      start_monitor(fn _ ->
        send(test_pid, {:probing, self()})

        receive do
          :go -> :ok
        end
      end)

    assert_receive {:probing, probe_pid}
    assert StorageMonitor.status(name) == {:error, :not_probed}

    send(probe_pid, :go)
    assert await_status(name, :ok) == :ok
  end

  test "reports probe errors" do
    name = start_monitor(fn _ -> {:error, :econnrefused} end)
    assert await_status(name, {:error, :econnrefused}) == {:error, :econnrefused}
  end

  test "a stalled probe reports a timeout but is never overlapped by another" do
    test_pid = self()

    name =
      start_monitor(
        fn _ ->
          send(test_pid, {:probing, self()})

          receive do
            :go -> :ok
          end
        end,
        timeout_ms: 20,
        interval_ms: 1
      )

    assert_receive {:probing, probe_pid}
    assert await_status(name, {:error, :probe_timeout}) == {:error, :probe_timeout}
    refute_receive {:probing, _}, 100

    send(probe_pid, :go)
    assert await_status(name, :ok) == :ok
  end

  test "stopping the monitor terminates a pending probe" do
    test_pid = self()

    {:ok, monitor} =
      StorageMonitor.start_link(
        name: nil,
        config: %{},
        probe: fn _ ->
          send(test_pid, {:probing, self()})
          Process.sleep(:infinity)
        end
      )

    assert_receive {:probing, probe_pid}
    ref = Process.monitor(probe_pid)
    Process.unlink(monitor)
    GenServer.stop(monitor)

    assert_receive {:DOWN, ^ref, :process, ^probe_pid, _}
  end

  test "a nonexistent bucket is not ready, even though a GET of it reads as not found" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listener)
    acceptor = spawn_link(fn -> serve_no_such_bucket(listener) end)
    on_exit(fn -> Process.exit(acceptor, :kill) end)

    config = %{
      bucket: "missing",
      region: "us-east-1",
      access_key_id: "a",
      secret_access_key: "s",
      allow_http: true,
      endpoint: "http://127.0.0.1:#{port}"
    }

    assert {:error, :not_found} = Pulse.ObjectStore.get(config, "k")

    name = :"monitor_#{System.unique_integer([:positive])}"
    start_supervised!({StorageMonitor, name: name, config: config, interval_ms: 10_000})
    assert {:error, reason} = wait_for_error(name)
    assert reason =~ "NoSuchBucket"
  end

  defp serve_no_such_bucket(listener) do
    {:ok, socket} = :gen_tcp.accept(listener)

    spawn(fn ->
      {:ok, _request} = :gen_tcp.recv(socket, 0, 5_000)
      body = ~s(<?xml version="1.0"?><Error><Code>NoSuchBucket</Code></Error>)

      :gen_tcp.send(
        socket,
        "HTTP/1.1 404 Not Found\r\ncontent-type: application/xml\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n" <>
          body
      )

      :gen_tcp.close(socket)
    end)

    serve_no_such_bucket(listener)
  end

  # A LIST is a billed Class A request. Successful object-store traffic since
  # the previous probe already proves the bucket reachable.
  test "successful object-store requests stand in for the probe's LIST" do
    agent =
      start_supervised!(
        {Agent,
         fn ->
           %{
             objects: %{},
             reads: [],
             version: 0,
             hook: nil,
             faults: %{},
             barriers: %{},
             lists: 0,
             deletes: [],
             requests: []
           }
         end}
      )

    server = start_supervised!({Bandit, plug: {CompactionStore, agent: agent}, ip: {127, 0, 0, 1}, port: 0})
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

    config = %{
      bucket: "pulse",
      region: "us-east-1",
      access_key_id: "a",
      secret_access_key: "s",
      allow_http: true,
      endpoint: "http://127.0.0.1:#{port}"
    }

    name = :"monitor_#{System.unique_integer([:positive])}"
    # Drive checks explicitly, outside the automatic timer, so slow HTTP
    # requests or scheduling cannot turn a busy interval into an idle one.
    monitor = start_supervised!({StorageMonitor, name: name, config: config, interval_ms: 60_000})
    assert await_status(name, :ok) == :ok
    lists = fn -> Agent.get(agent, & &1.lists) end
    assert lists.() == 1

    # Busy: each check has a new successful request, so no LIST is needed.
    for n <- 1..3 do
      assert {:ok, _} = Pulse.ObjectStore.put(config, "k#{n}", "v")
      send(monitor, :probe)
      await_probe(monitor)
      assert lists.() == 1
      assert StorageMonitor.status(name) == :ok
    end

    # Idle: list on each check. A probe's own LIST cannot justify skipping
    # the next check, nor can an earlier successful PUT be reused.
    for expected <- 2..3 do
      send(monitor, :probe)
      await_probe(monitor)
      assert lists.() == expected
      assert StorageMonitor.status(name) == :ok
    end

    # Failed traffic does not stand in for a probe either.
    assert {:error, :not_found} = Pulse.ObjectStore.get(config, "missing")
    send(monitor, :probe)
    await_probe(monitor)
    assert lists.() == 4
    assert StorageMonitor.status(name) == :ok
  end

  # A status call alone can still return the previous :ok while the async
  # probe is running. Wait for completion before inspecting its effects.
  defp await_probe(monitor) do
    case :sys.get_state(monitor) do
      %{task: nil} -> :ok
      _ -> await_probe(monitor)
    end
  end

  test "a crashing probe is reported and does not kill the monitor" do
    name = start_monitor(fn _ -> exit(:boom) end)
    assert {:error, {:probe_crashed, _}} = wait_for_error(name)
    assert Process.alive?(Pulse.Runtime.whereis(name))
  end

  test "status is an error when the monitor is not running" do
    assert StorageMonitor.status(:nonexistent_monitor) == {:error, :monitor_not_running}
  end

  defp wait_for_error(name) do
    case StorageMonitor.status(name) do
      {:error, :not_probed} -> wait_for_error(name)
      other -> other
    end
  end
end
