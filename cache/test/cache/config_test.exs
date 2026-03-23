defmodule Cache.ConfigTest do
  use ExUnit.Case, async: false

  describe "cache_endpoint/0" do
    test "returns hostname extracted from node name" do
      cache_endpoint = Cache.Config.cache_endpoint()
      assert is_binary(cache_endpoint)
      refute String.contains?(cache_endpoint, "@")
    end
  end

  describe "distributed_kv_ssl_opts/1" do
    test "derives peer verification settings from the database URL" do
      ssl_opts =
        Cache.Config.distributed_kv_ssl_opts("ecto://user:password@aws.connect.psdb.cloud/cache_kv?ssl=true")

      assert ssl_opts[:verify] == :verify_peer
      assert ssl_opts[:cacertfile] == CAStore.file_path()
      assert ssl_opts[:server_name_indication] == ~c"aws.connect.psdb.cloud"

      assert [match_fun: match_fun] = ssl_opts[:customize_hostname_check]
      assert is_function(match_fun)
    end

    test "raises when the database URL has no hostname" do
      assert_raise ArgumentError, "DISTRIBUTED_KV_DATABASE_URL must include a hostname", fn ->
        Cache.Config.distributed_kv_ssl_opts("ecto:///cache_kv")
      end
    end
  end
end
