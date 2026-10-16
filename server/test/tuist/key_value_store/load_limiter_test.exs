defmodule Tuist.KeyValueStore.LoadLimiterTest do
  use ExUnit.Case, async: true

  alias Tuist.KeyValueStore.LoadLimiter

  test "coalesces in-flight calls but never retains completed values" do
    pool = start_pool()
    parent = self()

    first =
      Task.async(fn ->
        LoadLimiter.run(pool, :key, fn ->
          send(parent, {:started, self()})

          receive do
            :continue -> 42
          end
        end)
      end)

    assert_receive {:started, worker}
    second = Task.async(fn -> LoadLimiter.run(pool, :key, fn -> flunk("must coalesce") end) end)
    wait_for_waiters(pool, :key, 2)
    send(worker, :continue)
    assert Task.await(first) == {:ok, 42}
    assert Task.await(second) == {:ok, 42}
    assert LoadLimiter.run(pool, :key, fn -> 43 end) == {:ok, 43}
    refute Map.has_key?(:sys.get_state(pool), :values)
  end

  test "bounds jobs and same-key waiters without an uncached fallback" do
    pool = start_pool(max_concurrency: 1, max_pending_loads: 1, max_waiters: 1)
    parent = self()

    task =
      Task.async(fn ->
        LoadLimiter.run(pool, :key, fn ->
          send(parent, {:started, self()})

          receive do
            :continue -> :ok
          end
        end)
      end)

    assert_receive {:started, worker}
    assert LoadLimiter.run(pool, :other, fn -> flunk("must not run") end) == {:error, :overloaded}
    assert LoadLimiter.run(pool, :key, fn -> flunk("must not run") end) == {:error, :overloaded}
    send(worker, :continue)
    assert Task.await(task) == {:ok, :ok}
  end

  test "queue expiry does not terminate or replace running work" do
    pool = start_pool(max_concurrency: 1, queue_timeout: 20, load_timeout: 1_000)
    parent = self()

    task =
      Task.async(fn ->
        LoadLimiter.run(pool, :key, fn ->
          send(parent, {:started, self()})

          receive do
            :continue -> :ok
          end
        end)
      end)

    assert_receive {:started, worker}
    assert LoadLimiter.run(pool, :other, fn -> flunk("expired work must not start") end) == {:error, :overloaded}
    assert Process.alive?(worker)
    send(worker, :continue)
    assert Task.await(task) == {:ok, :ok}
  end

  test "soft timeouts keep the running slot and let the worker finish its cache write" do
    pool = start_pool(max_concurrency: 1, queue_timeout: 20, load_timeout: 20)
    parent = self()

    task =
      Task.async(fn ->
        LoadLimiter.run(pool, :key, fn ->
          send(parent, {:started, self()})

          receive do
            :continue -> send(parent, :cache_written)
          end
        end)
      end)

    assert_receive {:started, worker}
    assert Task.await(task) == {:error, :timeout}
    assert Process.alive?(worker)
    assert LoadLimiter.run(pool, :key, fn -> flunk("must not replace timed-out work") end) == {:error, :overloaded}
    assert LoadLimiter.run(pool, :other, fn -> flunk("must not exceed concurrency") end) == {:error, :overloaded}
    send(worker, :continue)
    assert_receive :cache_written
    wait_for_idle(pool)
    assert LoadLimiter.run(pool, :other, fn -> :recovered end) == {:ok, :recovered}
  end

  test "reports an exception once for coalesced callers" do
    parent = self()
    pool = start_pool(on_error: fn reason -> send(parent, {:reported, reason}) end)

    first =
      Task.async(fn ->
        LoadLimiter.run(pool, :key, fn ->
          send(parent, {:started, self()})

          receive do
            :continue -> raise "failed"
          end
        end)
      end)

    assert_receive {:started, worker}
    second = Task.async(fn -> LoadLimiter.run(pool, :key, fn -> flunk("must coalesce") end) end)
    wait_for_waiters(pool, :key, 2)
    send(worker, :continue)
    assert {:error, {:exception, %RuntimeError{}, _stack}} = Task.await(first)
    assert {:error, {:exception, %RuntimeError{}, _stack}} = Task.await(second)
    assert_receive {:reported, {:exception, %RuntimeError{}, _stack}}
    refute_receive {:reported, _reason}
  end

  test "worker death releases admission and propagates an error" do
    pool = start_pool()
    parent = self()

    task =
      Task.async(fn ->
        LoadLimiter.run(pool, :key, fn ->
          send(parent, {:started, self()})
          Process.sleep(:infinity)
        end)
      end)

    assert_receive {:started, worker}
    Process.exit(worker, :kill)
    assert Task.await(task) == {:error, {:exit, :killed}}
    assert LoadLimiter.run(pool, :key, fn -> :recovered end) == {:ok, :recovered}
  end

  test "unavailable admission never invokes the loader" do
    assert LoadLimiter.run(:missing_overview_load_pool, :key, fn -> flunk("must not run") end) == {:error, :unavailable}
  end

  test "propagates callers to workers" do
    pool = start_pool()
    caller = self()
    assert LoadLimiter.run(pool, :key, fn -> Process.get(:"$callers") end) == {:ok, [caller]}
  end

  defp start_pool(opts \\ []) do
    name = String.to_atom("overview_pool_#{System.unique_integer([:positive])}")
    start_supervised!({LoadLimiter, Keyword.put(opts, :name, name)})
    name
  end

  defp wait_for_waiters(pool, key, count, attempts \\ 100) do
    if length(:sys.get_state(pool).loads[key].waiters) == count do
      :ok
    else
      assert attempts > 0
      Process.sleep(5)
      wait_for_waiters(pool, key, count, attempts - 1)
    end
  end

  defp wait_for_idle(pool, attempts \\ 100) do
    if :sys.get_state(pool).running == 0 do
      :ok
    else
      assert attempts > 0
      Process.sleep(5)
      wait_for_idle(pool, attempts - 1)
    end
  end
end
