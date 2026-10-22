defmodule Tuist.OIDC.JWKSCacheTest do
  use ExUnit.Case, async: true

  import Cachex.Spec, only: [hook: 1]

  alias Tuist.KeyValueStore
  alias Tuist.OIDC.JWKSCache

  @cache :oidc_jwks_bound_test

  setup do
    start_supervised!({JWKSCache, cache: @cache, maximum_entries: 2})
    :ok
  end

  test "successful values are reused in the dedicated cache" do
    url = "https://keys.example/success"
    keys = %{"keys" => [%{"kty" => "RSA"}]}
    assert JWKSCache.get_or_update(url, fn -> keys end, cache: @cache) == keys
    assert JWKSCache.get_or_update(url, fn -> flunk("must reuse successful keys") end, cache: @cache) == keys
    assert KeyValueStore.get(["oidc", "workload-jwks", url], cache: @cache) == keys
    assert KeyValueStore.get(["oidc", "workload-jwks", url]) == nil
  end

  test "failed fetches do not consume cache entries" do
    parent = self()

    for _ <- 1..2 do
      assert JWKSCache.get_or_update(
               "https://keys.example/error",
               fn ->
                 send(parent, :failed_fetch)
                 nil
               end,
               cache: @cache
             ) == nil
    end

    assert_receive :failed_fetch
    assert_receive :failed_fetch
    assert Cachex.size(@cache) == 0
  end

  test "the configured pruning hook evicts excess entries and misses fetch again" do
    for i <- 1..3 do
      assert JWKSCache.get_or_update("https://keys.example/#{i}", fn -> i end, cache: @cache) == i
    end

    hook(name: name) = @cache |> Cachex.inspect(:cache) |> Cachex.Hook.locate(Cachex.Limit.Scheduled)
    send(name, :policy_check)
    :sys.get_state(name)
    assert Cachex.size(@cache) <= 2

    evicted =
      Enum.find(1..3, fn i ->
        is_nil(KeyValueStore.get(["oidc", "workload-jwks", "https://keys.example/#{i}"], cache: @cache))
      end)

    assert evicted
    parent = self()

    assert JWKSCache.get_or_update(
             "https://keys.example/#{evicted}",
             fn ->
               send(parent, :refetched)
               evicted
             end,
             cache: @cache
           ) == evicted

    assert_receive :refetched
  end
end
