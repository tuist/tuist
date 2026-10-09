defmodule Tuist.Authentication.TokenVerificationCacheTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Tuist.Authentication.TokenVerificationCache
  alias Tuist.Authentication.UnavailableError

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

  test "a concurrent production-cost burst performs exactly one real bcrypt verification", %{cache: cache} do
    secret = Base.encode64(:crypto.strong_rand_bytes(20))
    stored_hash = Bcrypt.hash_pwd_salt(secret, log_rounds: 12)
    assert String.starts_with?(stored_hash, "$2b$12$")

    expect(Bcrypt, :verify_pass, 1, fn ^secret, ^stored_hash ->
      Mimic.call_original(Bcrypt, :verify_pass, [secret, stored_hash])
    end)

    results =
      1..2_000
      |> Task.async_stream(fn _ -> TokenVerificationCache.verify_pass(secret, stored_hash, cache: cache) end,
        max_concurrency: 64,
        timeout: 30_000
      )
      |> Enum.to_list()

    assert length(results) == 2_000
    assert Enum.all?(results, &(&1 == {:ok, true}))
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

  test "proof fills and hits bypass suspended shared processes", %{cache: cache} do
    owner = :ets.info(String.to_existing_atom("#{cache}_flights"), :owner)
    courier = Process.whereis(String.to_existing_atom("#{cache}_courier"))
    :sys.suspend(owner)
    :sys.suspend(courier)

    try do
      expect(Bcrypt, :verify_pass, 2, fn _, "hash" -> true end)

      for secret <- ["first", "second"], _ <- 1..100 do
        assert TokenVerificationCache.verify_pass(secret, "hash", cache: cache)
      end
    after
      :sys.resume(owner)
      :sys.resume(courier)
    end
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

  test "an unexpected cached value is unavailable rather than a computed mismatch", %{cache: cache} do
    key = :crypto.hash(:sha256, :erlang.term_to_binary({"secret", "hash"}))
    :ok = Cachex.put(cache, key, false)
    reject(Bcrypt, :verify_pass, 2)
    assert_raise UnavailableError, fn -> TokenVerificationCache.verify_pass("secret", "hash", cache: cache) end
  end

  test "expired proofs require verification again" do
    cache = String.to_atom("expiring_proofs_#{UUIDv7.generate()}")
    start_supervised!({TokenVerificationCache, cache: cache, ttl: 20}, id: :expiring_proofs)
    expect(Bcrypt, :verify_pass, 2, fn "secret", "hash" -> true end)
    assert TokenVerificationCache.verify_pass("secret", "hash", cache: cache)
    Process.sleep(30)
    assert TokenVerificationCache.verify_pass("secret", "hash", cache: cache)
  end

  test "clearing display views does not evict proofs", %{cache: cache} do
    display_cache = String.to_atom("display_#{UUIDv7.generate()}")
    start_supervised!({Cachex, [display_cache, []]}, id: :display_cache)
    expect(Bcrypt, :verify_pass, 1, fn "secret", "hash" -> true end)
    assert TokenVerificationCache.verify_pass("secret", "hash", cache: cache)

    for _ <- 1..100, do: Cachex.clear(display_cache)
    assert TokenVerificationCache.verify_pass("secret", "hash", cache: cache)
  end

  test "a correct secret is unavailable, never invalid, when its flight cannot complete", %{cache: cache} do
    secret = Base.encode64(:crypto.strong_rand_bytes(20))
    stored_hash = Bcrypt.hash_pwd_salt(secret, log_rounds: 12)
    assert Mimic.call_original(Bcrypt, :verify_pass, [secret, stored_hash])
    reject(Bcrypt, :verify_pass, 2)
    key = :crypto.hash(:sha256, :erlang.term_to_binary({secret, stored_hash}))
    table = String.to_existing_atom("#{cache}_flights")
    coordinator = spawn(fn -> Process.sleep(:infinity) end)
    on_exit(fn -> Process.exit(coordinator, :kill) end)
    :ets.insert(table, {key, coordinator})

    assert_raise UnavailableError, fn ->
      TokenVerificationCache.verify_pass(secret, stored_hash, cache: cache, timeout: 100)
    end
  end

  test "cache failure rejects verification instead of rerunning bcrypt" do
    reject(Bcrypt, :verify_pass, 2)

    assert_raise UnavailableError, fn ->
      TokenVerificationCache.verify_pass("secret", "hash", cache: :missing_token_proof_cache)
    end
  end
end
