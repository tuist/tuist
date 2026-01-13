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
end
