defmodule Tuist.KeyValueStore.InvalidatorTest do
  use ExUnit.Case, async: false

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
