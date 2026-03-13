defmodule Cache.ConfigTest do
  use ExUnit.Case, async: false

  setup do
    original = Application.get_env(:cache, :distributed_kv_remote_fallback_enabled)

    on_exit(fn ->
      Application.put_env(:cache, :distributed_kv_remote_fallback_enabled, original)
    end)

    :ok
  end

  describe "cache_endpoint/0" do
    test "returns hostname extracted from node name" do
      cache_endpoint = Cache.Config.cache_endpoint()
      assert is_binary(cache_endpoint)
      refute String.contains?(cache_endpoint, "@")
    end
  end

  describe "distributed_kv_remote_fallback_enabled?/0" do
    test "defaults to false" do
      Application.delete_env(:cache, :distributed_kv_remote_fallback_enabled)

      refute Cache.Config.distributed_kv_remote_fallback_enabled?()
    end

    test "returns true when explicitly enabled" do
      Application.put_env(:cache, :distributed_kv_remote_fallback_enabled, true)

      assert Cache.Config.distributed_kv_remote_fallback_enabled?()
    end
  end
end
