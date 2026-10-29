defmodule Tuist.Authentication.SingleFlightTest do
  use ExUnit.Case, async: false

  alias Tuist.Authentication.SingleFlight
  alias Tuist.Authentication.TokenVerificationCache

  setup do
    cache = String.to_atom("single_flight_#{UUIDv7.generate()}")
    supervisor = start_supervised!({TokenVerificationCache, cache: cache})
    table = :ets.whereis(String.to_existing_atom("#{cache}_flights"))
    %{cache: cache, table: table, supervisor: supervisor}
  end

  test "cold keys make progress with both shared coordination processes suspended", %{cache: cache, table: table} do
    owner = :ets.info(table, :owner)
    courier = Process.whereis(String.to_existing_atom("#{cache}_courier"))
    :sys.suspend(owner)
    :sys.suspend(courier)
    parent = self()

    try do
      tasks =
        for key <- 1..64 do
          Task.async(fn ->
            SingleFlight.fetch(cache, key, fn ->
              send(parent, {:filling, key, self()})

              receive do
                :finish -> {:commit, key}
              end
            end)
          end)
        end

      workers =
        for _ <- 1..64 do
          assert_receive {:filling, key, pid}, 5_000
          {key, pid}
        end

      assert length(Enum.uniq_by(workers, &elem(&1, 1))) == 64
      for {_, pid} <- workers, do: send(pid, :finish)
      assert Enum.map(tasks, &Task.await(&1, 5_000)) == Enum.map(1..64, &{:commit, &1})
      for key <- 1..64, do: assert(SingleFlight.fetch(cache, key, fn -> flunk("warm fill") end) == key)
      assert :ets.info(table, :size) == 0
    after
      :sys.resume(owner)
      :sys.resume(courier)
    end
  end

  test "worker crashes release the key and permit a later fill", %{cache: cache, table: table} do
    assert SingleFlight.fetch(cache, :key, fn -> exit(:failed) end) == {:error, :unavailable}
    assert :ets.info(table, :size) == 0
    assert SingleFlight.fetch(cache, :key, fn -> {:commit, :valid} end) == {:commit, :valid}
  end

  test "a crashed coordinator cannot leave a stuck claim", %{cache: cache, table: table} do
    dead = spawn(fn -> :ok end)
    ref = Process.monitor(dead)
    assert_receive {:DOWN, ^ref, :process, ^dead, _}
    :ets.insert(table, {:key, dead})
    assert SingleFlight.fetch(cache, :key, fn -> {:commit, :valid} end) == {:commit, :valid}
    assert :ets.info(table, :size) == 0
  end

  test "coordinator death cancels its worker and releases the claim", %{cache: cache, table: table} do
    parent = self()

    task =
      Task.async(fn ->
        SingleFlight.fetch(cache, :key, fn ->
          send(parent, {:worker, self()})

          receive do
            :finish -> {:commit, :late}
          end
        end)
      end)

    assert_receive {:worker, pid}
    ref = Process.monitor(pid)
    [{:key, coordinator}] = :ets.lookup(table, :key)
    Process.exit(coordinator, :kill)
    assert Task.await(task) == {:error, :unavailable}
    assert_receive {:DOWN, ^ref, :process, ^pid, _}
    assert :ets.info(table, :size) == 0
    assert SingleFlight.fetch(cache, :key, fn -> {:commit, :fresh} end) == {:commit, :fresh}
  end

  test "a timed-out fill is cancelled and cannot write later", %{cache: cache, table: table} do
    parent = self()

    task =
      Task.async(fn ->
        SingleFlight.fetch(
          cache,
          :key,
          fn ->
            send(parent, {:worker, self()})

            receive do
              :finish -> {:commit, :late}
            end
          end,
          timeout: 100
        )
      end)

    assert_receive {:worker, pid}
    ref = Process.monitor(pid)
    assert Task.await(task) == {:error, :unavailable}
    assert_receive {:DOWN, ^ref, :process, ^pid, _}
    assert Cachex.get(cache, :key) == nil
    assert :ets.info(table, :size) == 0
    assert SingleFlight.fetch(cache, :key, fn -> {:commit, :fresh} end) == {:commit, :fresh}
  end

  test "an exhausted budget starts no fill", %{cache: cache, table: table} do
    assert SingleFlight.fetch(cache, :key, fn -> flunk("expired fill") end, timeout: 0) == {:error, :unavailable}
    assert :ets.info(table, :size) == 0
  end

  test "errors and negative results are not retained", %{cache: cache} do
    assert SingleFlight.fetch(cache, :key, fn -> {:ignore, false} end) == {:ignore, false}
    assert SingleFlight.fetch(cache, :key, fn -> raise "unavailable" end) == {:error, :unavailable}
    assert SingleFlight.fetch(cache, :key, fn -> {:ignore, nil} end) == {:ignore, nil}
    assert Cachex.size(cache) == 0
  end

  test "a stalled coordinator cannot permit publication after the deadline", %{cache: cache, table: table} do
    parent = self()

    task =
      Task.async(fn ->
        SingleFlight.fetch(
          cache,
          :key,
          fn ->
            send(parent, {:worker, self()})

            receive do
              :finish -> {:commit, :late}
            end
          end,
          timeout: 100
        )
      end)

    assert_receive {:worker, worker}, 5_000
    [{:key, coordinator}] = :ets.lookup(table, :key)
    :erlang.suspend_process(coordinator)
    :erlang.suspend_process(task.pid)

    try do
      Process.sleep(150)
      ref = Process.monitor(worker)
      send(worker, :finish)
      assert_receive {:DOWN, ^ref, :process, ^worker, _}, 5_000
      assert Cachex.get(cache, :key) == nil
    after
      :erlang.resume_process(task.pid)
      Process.exit(coordinator, :kill)
    end

    assert Task.await(task, 5_000) == {:error, :unavailable}
  end

  test "an old worker cannot publish into the restarted cache with its coordinator stalled", %{cache: cache, table: table} do
    parent = self()

    task =
      Task.async(fn ->
        SingleFlight.fetch(cache, :key, fn ->
          send(parent, {:worker, self()})

          receive do
            :finish -> {:commit, :old_generation}
          end
        end)
      end)

    assert_receive {:worker, worker}, 5_000
    [{:key, coordinator}] = :ets.lookup(table, :key)
    :erlang.suspend_process(coordinator)

    try do
      Process.exit(:ets.info(table, :owner), :kill)
      wait_for_restart(cache, table, 500)
      ref = Process.monitor(worker)
      send(worker, :finish)
      assert_receive {:DOWN, ^ref, :process, ^worker, _}, 5_000
      assert Cachex.get(cache, :key) == nil
      assert SingleFlight.fetch(cache, :key, fn -> {:commit, :fresh} end) == {:commit, :fresh}
    after
      Process.exit(coordinator, :kill)
    end

    assert Task.await(task, 5_000) == {:error, :unavailable}
  end

  test "publication targets the captured data table even if only Cachex restarts", %{cache: cache, supervisor: supervisor} do
    parent = self()

    task =
      Task.async(fn ->
        SingleFlight.fetch(cache, :key, fn ->
          send(parent, {:worker, self()})

          receive do
            :finish -> {:commit, :old_generation}
          end
        end)
      end)

    assert_receive {:worker, worker}, 5_000
    old_data = :ets.whereis(cache)
    :ok = Supervisor.terminate_child(supervisor, Cachex)
    {:ok, _} = Supervisor.restart_child(supervisor, Cachex)
    assert :ets.whereis(cache) != old_data
    send(worker, :finish)
    assert Task.await(task, 5_000) == {:error, :unavailable}
    assert Cachex.get(cache, :key) == nil
  end

  test "a short-lived waiter never cancels another caller's healthy flight", %{cache: cache} do
    parent = self()

    initiator =
      Task.async(fn ->
        SingleFlight.fetch(cache, :key, fn ->
          send(parent, {:worker, self()})

          receive do
            :finish -> {:commit, :valid}
          end
        end)
      end)

    assert_receive {:worker, worker}, 5_000
    assert SingleFlight.fetch(cache, :key, fn -> flunk("duplicate fill") end, timeout: 50) == {:error, :unavailable}
    assert Process.alive?(worker)
    send(worker, :finish)
    assert Task.await(initiator, 5_000) == {:commit, :valid}
  end

  test "a waiter retries a failed flight within its own remaining budget", %{cache: cache, table: table} do
    parent = self()

    initiator =
      Task.async(fn ->
        SingleFlight.fetch(
          cache,
          :key,
          fn ->
            send(parent, {:worker, self()})

            receive do
              :finish -> {:commit, :never}
            end
          end,
          timeout: 100
        )
      end)

    assert_receive {:worker, _}, 5_000
    [{:key, coordinator}] = :ets.lookup(table, :key)
    :erlang.suspend_process(coordinator)
    :erlang.suspend_process(initiator.pid)
    waiter = Task.async(fn -> SingleFlight.fetch(cache, :key, fn -> {:commit, :valid} end) end)

    try do
      wait_for_monitor(coordinator, waiter.pid, 500)
      :erlang.resume_process(initiator.pid)
      assert Task.await(initiator, 5_000) == {:error, :unavailable}
      assert Task.await(waiter, 5_000) == {:commit, :valid}
      assert Cachex.get(cache, :key) == :valid
    after
      Process.exit(coordinator, :kill)
    end
  end

  test "owner loss cancels active work instead of orphaning it", %{cache: cache, table: table} do
    parent = self()

    task =
      Task.async(fn ->
        SingleFlight.fetch(cache, :key, fn ->
          send(parent, {:worker, self()})

          receive do
            :finish -> {:commit, :late}
          end
        end)
      end)

    assert_receive {:worker, pid}
    ref = Process.monitor(pid)
    Process.exit(:ets.info(table, :owner), :kill)
    assert Task.await(task) == {:error, :unavailable}
    assert_receive {:DOWN, ^ref, :process, ^pid, _}
  end

  defp wait_for_restart(_cache, _table, 0), do: flunk("cache did not restart")

  defp wait_for_restart(cache, table, retries) do
    if :ets.whereis(String.to_existing_atom("#{cache}_flights")) in [:undefined, table] do
      Process.sleep(10)
      wait_for_restart(cache, table, retries - 1)
    end
  end

  defp wait_for_monitor(_coordinator, _waiter, 0), do: flunk("waiter did not join the flight")

  defp wait_for_monitor(coordinator, waiter, retries) do
    {:monitored_by, monitors} = Process.info(coordinator, :monitored_by)

    if waiter not in monitors do
      Process.sleep(10)
      wait_for_monitor(coordinator, waiter, retries - 1)
    end
  end
end
