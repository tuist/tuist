defmodule Cache.Finch.PoolsTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Cache.Finch.Pools

  setup :set_mimic_from_context

  describe "config/0 S3 pool protocols" do
    setup do
      stub(Cache.Config, :server_url, fn -> "https://tuist.dev" end)

      stub(Cache.Config, :s3_config, fn ->
        {:ok, [scheme: "https://", host: "s3.example.com", region: "us-east-1"]}
      end)

      :ok
    end

    test "uses configured S3 protocol for S3 pool" do
      stub(Cache.Config, :s3_protocols, fn -> [:http1] end)

      config = Pools.config()
      s3_pool = Map.get(config, "https://s3.example.com")

      assert s3_pool
      assert Keyword.get(s3_pool, :protocols) == [:http1]
      assert Keyword.get(s3_pool[:conn_opts], :protocols) == [:http1]
    end

    test "uses http2 for S3 pool when configured" do
      stub(Cache.Config, :s3_protocols, fn -> [:http2] end)

      config = Pools.config()
      s3_pool = Map.get(config, "https://s3.example.com")

      assert Keyword.get(s3_pool, :protocols) == [:http2]
      assert Keyword.get(s3_pool[:conn_opts], :protocols) == [:http2]
    end

    test "server pool keeps its own protocols regardless of S3 config" do
      stub(Cache.Config, :s3_protocols, fn -> [:http1] end)

      config = Pools.config()
      server_pool = Map.get(config, "https://tuist.dev")

      assert Keyword.get(server_pool, :protocols) == [:http2, :http1]
      assert Keyword.get(server_pool[:conn_opts], :protocols) == [:http2, :http1]
    end

    test "defaults S3 protocols to [:http2, :http1] when not configured" do
      config = Pools.config()
      s3_pool = Map.get(config, "https://s3.example.com")

      assert Keyword.get(s3_pool, :protocols) == [:http2, :http1]
    end
  end
end
