defmodule Tuist.Authentication.TokenVerificationCacheTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Tuist.Authentication.TokenVerificationCache
  alias Tuist.KeyValueStore.Invalidator

  setup :set_mimic_global

  setup do
    cache = String.to_atom("token_proofs_#{UUIDv7.generate()}")
    start_supervised!({TokenVerificationCache, cache: cache})
    {:ok, cache: cache}
  end

  test "repeated hot-path requests verify bcrypt once", %{cache: cache} do
    expect(Bcrypt, :verify_pass, 1, fn "secret", "stored-hash" -> true end)

    for _ <- 1..1_000 do
      assert TokenVerificationCache.verify_pass("secret", "stored-hash", cache: cache)
    end
  end

  test "concurrent cold requests share one verification", %{cache: cache} do
    expect(Bcrypt, :verify_pass, 1, fn "secret", "stored-hash" ->
      Process.sleep(50)
      true
    end)

    results =
      1..100
      |> Task.async_stream(fn _ -> TokenVerificationCache.verify_pass("secret", "stored-hash", cache: cache) end,
        max_concurrency: 100
      )
      |> Enum.to_list()

    assert Enum.all?(results, &(&1 == {:ok, true}))
  end

  test "a cold credential does not block unrelated credentials", %{cache: cache} do
    parent = self()

    stub(Bcrypt, :verify_pass, fn
      "slow", "hash" ->
        send(parent, {:verifying, self()})

        receive do
          :continue -> true
        end

      "fast", "hash" ->
        true
    end)

    slow = Task.async(fn -> TokenVerificationCache.verify_pass("slow", "hash", cache: cache) end)
    assert_receive {:verifying, worker}
    fast = Task.async(fn -> TokenVerificationCache.verify_pass("fast", "hash", cache: cache) end)
    assert Task.await(fast, 1_000)
    send(worker, :continue)
    assert Task.await(slow)
  end

  test "proofs bind both the secret and the stored hash", %{cache: cache} do
    expect(Bcrypt, :verify_pass, fn "secret", "old-hash" -> true end)
    expect(Bcrypt, :verify_pass, fn "wrong", "old-hash" -> false end)
    expect(Bcrypt, :verify_pass, fn "secret", "new-hash" -> false end)

    assert TokenVerificationCache.verify_pass("secret", "old-hash", cache: cache)
    refute TokenVerificationCache.verify_pass("wrong", "old-hash", cache: cache)
    refute TokenVerificationCache.verify_pass("secret", "new-hash", cache: cache)
  end

  test "does not cache failed verifications", %{cache: cache} do
    expect(Bcrypt, :verify_pass, 2, fn "wrong", "hash" -> false end)
    refute TokenVerificationCache.verify_pass("wrong", "hash", cache: cache)
    refute TokenVerificationCache.verify_pass("wrong", "hash", cache: cache)
    assert Cachex.size(cache) == 0
  end

  test "expired proofs require verification again" do
    cache = String.to_atom("expiring_proofs_#{UUIDv7.generate()}")
    start_supervised!({TokenVerificationCache, cache: cache, ttl: 20}, id: :expiring_proofs)
    expect(Bcrypt, :verify_pass, 2, fn "secret", "hash" -> true end)
    assert TokenVerificationCache.verify_pass("secret", "hash", cache: cache)
    Process.sleep(30)
    assert TokenVerificationCache.verify_pass("secret", "hash", cache: cache)
  end

  test "display invalidations and membership flapping do not evict proofs", %{cache: cache} do
    display_cache = String.to_atom("display_#{UUIDv7.generate()}")
    start_supervised!({Cachex, [display_cache, []]}, id: :display_cache)
    invalidator = start_supervised!({Invalidator, cache: display_cache, name: nil})
    expect(Bcrypt, :verify_pass, 1, fn "secret", "hash" -> true end)
    assert TokenVerificationCache.verify_pass("secret", "hash", cache: cache)

    for _ <- 1..50, event <- [:nodeup, :nodedown] do
      send(invalidator, {event, :flapping_peer})
    end

    :sys.get_state(invalidator)
    assert TokenVerificationCache.verify_pass("secret", "hash", cache: cache)
  end

  test "cache failure rejects verification instead of rerunning bcrypt" do
    reject(Bcrypt, :verify_pass, 2)
    refute TokenVerificationCache.verify_pass("secret", "hash", cache: :missing_token_proof_cache)
  end
end
