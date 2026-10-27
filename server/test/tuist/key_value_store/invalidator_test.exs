defmodule Tuist.KeyValueStore.InvalidatorTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.KeyValueStore.Invalidator

  setup do
    cache = String.to_atom("scale_cache_#{System.unique_integer([:positive])}")
    start_supervised!({Cachex, [cache, []]})
    pid = start_supervised!({Invalidator, name: nil, cache: cache})
    %{cache: cache, pid: pid}
  end

  test "removes broadcast keys while preserving unrelated entries", %{cache: cache, pid: pid} do
    Cachex.put(cache, "balance", :stale)
    Cachex.put(cache, "other", :current)
    Invalidator.broadcast("balance")
    # Barrier on this subscriber's mailbox after publish/subscribe delivery.
    eventually(fn -> Cachex.get(cache, "balance") == nil end)
    assert Cachex.get(cache, "other") == :current
    assert Process.alive?(pid)
  end

  test "clears entries after node departure and rejoin", %{cache: cache, pid: pid} do
    for event <- [:nodedown, :nodeup] do
      Cachex.put(cache, "balance", :stale)
      send(pid, {event, :"other@127.0.0.1"})
      :sys.get_state(pid)
      assert Cachex.get(cache, "balance") == nil
    end
  end

  test "membership flapping leaves independent immutable caches intact", %{cache: cache, pid: pid} do
    protected = String.to_atom("immutable_cache_#{System.unique_integer([:positive])}")
    start_supervised!({Cachex, [protected, []]}, id: :immutable_cache)
    Cachex.put(protected, "bcrypt-proof", true)

    for _ <- 1..50, event <- [:nodeup, :nodedown] do
      Cachex.put(cache, "display", :stale)
      send(pid, {event, :flapping_peer})
    end

    :sys.get_state(pid)
    assert Cachex.get(cache, "display") == nil
    assert Cachex.get(protected, "bcrypt-proof") == true
  end

  test "membership recovery leaves general request, authentication and license caches warm" do
    key = "protected-#{System.unique_integer([:positive])}"
    caches = [:tuist, :license, :token_verification, :auth_subjects]
    Enum.each([:display | caches], &Cachex.put(&1, key, :warm))
    on_exit(fn -> Enum.each([:display | caches], &Cachex.del(&1, key)) end)

    pid = Process.whereis(Invalidator)
    send(pid, {:nodeup, :rejoined_peer})
    :sys.get_state(pid)

    assert Cachex.get(:display, key) == nil
    Enum.each(caches, fn cache -> assert Cachex.get(cache, key) == :warm end)
  end

  test "display invalidation does not delete a subsequent local replacement", %{cache: cache} do
    key = "display-#{System.unique_integer([:positive])}"
    on_exit(fn -> Cachex.del(:display, key) end)
    Cachex.put(cache, key, :remote_stale)
    KeyValueStore.put(key, :local_stale, cache: :display)

    assert KeyValueStore.invalidate(key, cache: :display) == :ok
    KeyValueStore.put(key, :fresh, cache: :display)
    eventually(fn -> Cachex.get(cache, key) == nil end)
    :sys.get_state(Invalidator)
    assert KeyValueStore.get(key, cache: :display) == :fresh
  end

  test "persistent invalidation deletes the normalized shared key", %{cache: cache} do
    stub(Environment, :redis_url, fn -> "redis://unused" end)
    expect(Redix, :command, fn _conn, ["DEL", "persistent-balance"] -> {:ok, 1} end)
    Cachex.put(cache, "persistent-balance", :stale)

    assert KeyValueStore.invalidate([:persistent, :balance], cache: cache, persist_across_deployments: true) == :ok
    assert Cachex.get(cache, "persistent-balance") == nil
  end

  for failure <- [:returned_connection, :raised_connection, :redis_error] do
    @failure failure
    test "persistent #{@failure} still invalidates display fallbacks and reports the failure", %{cache: cache} do
      key = "redis-failure-#{System.unique_integer([:positive])}"
      stub(Environment, :redis_url, fn -> "redis://unused" end)
      failure = @failure

      expect(Redix, :command, fn _conn, ["DEL", ^key] ->
        redis_failure(failure)
      end)

      Cachex.put(cache, key, :stale)
      KeyValueStore.put(key, :stale, cache: :display)
      on_exit(fn -> Cachex.del(:display, key) end)

      assert {:error, _} = KeyValueStore.invalidate(key, cache: :display, persist_across_deployments: true)
      assert Cachex.get(:display, key) == nil
      eventually(fn -> Cachex.get(cache, key) == nil end)
    end
  end

  defp redis_failure(:returned_connection), do: {:error, %Redix.ConnectionError{reason: :closed}}
  defp redis_failure(:raised_connection), do: raise(Redix.ConnectionError, reason: :closed)
  defp redis_failure(:redis_error), do: {:error, %Redix.Error{message: "NOPERM"}}

  defp eventually(predicate) do
    result =
      Enum.reduce_while(1..100, false, fn _, _ ->
        if predicate.(),
          do: {:halt, true},
          else:
            (
              Process.sleep(10)
              {:cont, false}
            )
      end)

    assert result
  end
end
