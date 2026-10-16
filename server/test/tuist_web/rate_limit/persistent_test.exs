defmodule TuistWeb.RateLimit.PersistentTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Environment
  alias TuistWeb.RateLimit
  alias TuistWeb.RateLimit.PersistentFixedWindow
  alias TuistWeb.RateLimit.PersistentTokenBucket
  alias TuistWeb.RateLimit.RedisPool

  setup do
    owner = self()

    stub(RedisPool, :connection, fn name ->
      send(owner, {:connection, name})
      owner
    end)

    %{owner: owner, key: "persistent:#{UUIDv7.generate()}", window: System.system_time(:millisecond) * 2}
  end

  test "fixed windows preserve the shared namespace, increment, expiration and timeout", %{
    owner: owner,
    key: key,
    window: window
  } do
    stub(Redix, :pipeline!, fn conn, commands, opts ->
      send(owner, {:pipeline, conn, commands, opts})
      [7, 1]
    end)

    assert {:allow, 7} = PersistentFixedWindow.hit(key, window, 10, 7)
    assert_received {:connection, PersistentFixedWindow}
    full_key = "TuistWeb.RateLimit.PersistentFixedWindow:#{key}:0"
    expires_at = div(window, 1000)

    assert_received {:pipeline, ^owner, [["INCRBY", ^full_key, 7], ["EXPIREAT", ^full_key, ^expires_at, "NX"]],
                     [timeout: 500]}
  end

  test "fixed-window denials are not weakened by partitioning", %{owner: owner, key: key, window: window} do
    stub(Redix, :pipeline!, fn conn, commands, opts ->
      send(owner, {:pipeline, conn, commands, opts})
      [11, 1]
    end)

    assert {:deny, retry_after} = PersistentFixedWindow.hit(key, window, 10)
    assert retry_after > 0
    assert retry_after <= window
    assert_received {:connection, PersistentFixedWindow}
    assert_received {:pipeline, ^owner, [["INCRBY", _, 1], _], [timeout: 500]}
  end

  test "fixed-window get, increment and set retain the existing helper contracts", %{
    owner: owner,
    key: key,
    window: window
  } do
    stub(Redix, :pipeline!, fn conn, commands, opts ->
      send(owner, {:pipeline, conn, commands, opts})
      [9, 1]
    end)

    stub(Redix, :command!, fn conn, command, opts ->
      send(owner, {:command, conn, command, opts})
      "9"
    end)

    assert PersistentFixedWindow.inc(key, window) == 9
    assert PersistentFixedWindow.set(key, window, 9) == 9
    assert PersistentFixedWindow.get(key, window) == 9
    full_key = "TuistWeb.RateLimit.PersistentFixedWindow:#{key}:0"
    assert_received {:pipeline, ^owner, [["INCRBY", ^full_key, 1], _], [timeout: 500]}
    assert_received {:pipeline, ^owner, [["SET", ^full_key, 9], _], [timeout: 500]}
    assert_received {:command, ^owner, ["GET", ^full_key], [timeout: 500]}
  end

  test "token buckets retain the existing script, namespace, cost and timeout", %{owner: owner, key: key} do
    stub(Redix, :command, fn conn, command, opts ->
      send(owner, {:command, conn, command, opts})
      {:ok, [1, 9]}
    end)

    assert {:allow, 9} = PersistentTokenBucket.hit(key, 2, 10, 3)
    assert_received {:connection, PersistentTokenBucket}
    full_key = "TuistWeb.RateLimit.PersistentTokenBucket:#{key}"
    assert_received {:command, ^owner, ["EVAL", script, "1", ^full_key, 10, 2, 3], [timeout: 500]}
    assert script =~ ~s|redis.call("TIME")|
  end

  test "token buckets preserve denial and get behavior", %{owner: owner, key: key, window: window} do
    stub(Redix, :command, fn conn, command, opts ->
      send(owner, {:command, conn, command, opts})
      if hd(command) == "EVAL", do: {:ok, [0, 0]}, else: {:ok, "4"}
    end)

    assert {:deny, 1000} = PersistentTokenBucket.hit(key, 1, 10)
    assert PersistentTokenBucket.get(key, window) == 4
    assert function_exported?(PersistentTokenBucket, :get, 2)
    refute function_exported?(PersistentTokenBucket, :get, 1)
    full_key = "TuistWeb.RateLimit.PersistentTokenBucket:#{key}"
    assert_received {:command, ^owner, ["HGET", ^full_key, "level"], [timeout: 500]}
  end

  for algorithm <- [:fixed_window, :token_bucket], policy <- [:deny, :local], failure <- [:missing, :stale] do
    @algorithm algorithm
    @policy policy
    @failure failure
    test "a #{@failure} #{@algorithm} connection follows the #{@policy} failure policy", %{key: key, window: window} do
      stub(Environment, :redis_url, fn -> "redis://unavailable" end)
      stub(Environment, :rate_limit_fallback_replicas, fn -> 5 end)

      if @failure == :missing do
        stub(RedisPool, :connection, fn _ -> exit(:noproc) end)
      else
        {pid, monitor} = spawn_monitor(fn -> :ok end)
        assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}
        stub(RedisPool, :connection, fn _ -> pid end)
      end

      opts =
        if @algorithm == :fixed_window,
          do: [limit: 100, window: window, failure_policy: @policy],
          else: [algorithm: :token_bucket, capacity: 10, refill_rate: 1, failure_policy: @policy]

      result = RateLimit.hit(key, opts)

      if @algorithm == :fixed_window and @policy == :local do
        assert {:allow, 1} = result
      else
        assert {:deny, _} = result
      end
    end
  end
end
