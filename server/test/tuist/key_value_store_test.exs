defmodule Tuist.KeyValueStoreTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.KeyValueStore

  describe "get/2" do
    test "returns nil when key is not found in cachex" do
      # When
      result = KeyValueStore.get([:test, "key"])

      # Then
      assert result == nil
    end

    test "returns cached value from cachex when present" do
      # Given
      cache_key = [:test, "cached_key"]
      expected_value = %{data: "test_value"}
      Cachex.put(:tuist, "test-cached_key", expected_value)

      # When
      result = KeyValueStore.get(cache_key)

      # Then
      assert result == expected_value
    end

    test "returns cached value from redis when available" do
      # Given
      cache_key = [:redis, "test_key"]
      expected_value = %{data: "redis_value"}

      stub(Tuist.Environment, :redis_url, fn -> "redis://localhost:6379" end)

      expect(Redix, :command, fn _conn, ["GET", "redis-test_key"] ->
        {:ok, :erlang.term_to_binary(expected_value)}
      end)

      # When
      result = KeyValueStore.get(cache_key, persist_across_deployments: true)

      # Then
      assert result == expected_value
    end

    test "returns nil from redis when key is not found" do
      # Given
      cache_key = [:redis, "missing_key"]

      stub(Tuist.Environment, :redis_url, fn -> "redis://localhost:6379" end)

      expect(Redix, :command, fn _conn, ["GET", "redis-missing_key"] ->
        {:ok, nil}
      end)

      # When
      result = KeyValueStore.get(cache_key, persist_across_deployments: true)

      # Then
      assert result == nil
    end

    test "falls back to cachex when redis connection fails" do
      # Given
      cache_key = [:redis, "fallback_key"]
      expected_value = %{data: "cachex_fallback"}

      stub(Tuist.Environment, :redis_url, fn -> "redis://localhost:6379" end)

      expect(Redix, :command, fn _conn, ["GET", "redis-fallback_key"] ->
        raise Redix.ConnectionError, reason: :closed
      end)

      Cachex.put(:tuist, "redis-fallback_key", expected_value)

      # When
      result = KeyValueStore.get(cache_key, persist_across_deployments: true)

      # Then
      assert result == expected_value
    end

    test "uses custom cache when specified" do
      # Given
      cache_key = [:custom, "cache_key"]
      expected_value = "custom_cache_value"
      Cachex.put(:tuist, "custom-cache_key", expected_value)

      # When
      result = KeyValueStore.get(cache_key, cache: :tuist)

      # Then
      assert result == expected_value
    end
  end

  describe "put/3" do
    test "stores a value in cachex" do
      cache_key = [:put, "cachex_key"]
      value = %{data: "cachex_value"}

      assert {:ok, true} = KeyValueStore.put(cache_key, value)
      assert KeyValueStore.get(cache_key) == value
    end

    test "supports atom keys documented in the examples" do
      cache_key = :key_value_store_atom_key
      value = "atom-key-value"
      Cachex.del(:tuist, "key_value_store_atom_key")

      assert {:ok, true} = KeyValueStore.put(cache_key, value)
      assert KeyValueStore.get(cache_key) == value
    end

    test "uses a custom cache when specified" do
      cache = :"key_value_store_put_#{System.unique_integer([:positive])}"
      {:ok, _pid} = Cachex.start_link(name: cache)
      cache_key = [:put, "custom_cache_key"]
      value = "custom-cache-value"

      assert {:ok, true} = KeyValueStore.put(cache_key, value, cache: cache)
      assert KeyValueStore.get(cache_key, cache: cache) == value
    end

    test "stores a value in redis when persistence is enabled" do
      cache_key = [:redis, "put_key"]
      value = %{data: "redis_value"}

      stub(Tuist.Environment, :redis_url, fn -> "redis://localhost:6379" end)

      expect(Redix, :command, fn _conn, ["SET", "redis-put_key", serialized_value, "EX", 2] ->
        assert :erlang.binary_to_term(serialized_value) == value
        {:ok, "OK"}
      end)

      assert {:ok, "OK"} =
               KeyValueStore.put(cache_key, value, persist_across_deployments: true, ttl: 2000)
    end

    test "falls back to cachex when redis connection fails" do
      cache_key = [:redis, "put_fallback_key"]
      value = %{data: "cachex_fallback"}

      stub(Tuist.Environment, :redis_url, fn -> "redis://localhost:6379" end)

      expect(Redix, :command, fn _conn, ["SET", "redis-put_fallback_key", _value, "EX", 60] ->
        raise Redix.ConnectionError, reason: :closed
      end)

      assert {:ok, true} = KeyValueStore.put(cache_key, value, persist_across_deployments: true)
      assert KeyValueStore.get(cache_key) == value
    end
  end
end
