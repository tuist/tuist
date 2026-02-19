defmodule Cache.Finch.PoolsTest do
  use ExUnit.Case, async: false

  alias Cache.Finch.Pools

  describe "config/0 S3 pool protocols" do
    test "uses configured S3 protocol for S3 pool" do
      Application.put_env(:cache, :server_url, "https://tuist.dev")

      Application.put_env(:cache, :s3,
        bucket: "test-bucket",
        protocols: [:http1]
      )

      Application.put_env(:ex_aws, :s3,
        scheme: "https://",
        host: "s3.example.com",
        region: "us-east-1"
      )

      config = Pools.config()
      s3_pool = Map.get(config, "https://s3.example.com")

      assert s3_pool
      assert Keyword.get(s3_pool, :protocols) == [:http1]
      assert Keyword.get(s3_pool[:conn_opts], :protocols) == [:http1]
    end

    test "uses http2 for S3 pool when configured" do
      Application.put_env(:cache, :server_url, "https://tuist.dev")

      Application.put_env(:cache, :s3,
        bucket: "test-bucket",
        protocols: [:http2]
      )

      Application.put_env(:ex_aws, :s3,
        scheme: "https://",
        host: "s3.example.com",
        region: "us-east-1"
      )

      config = Pools.config()
      s3_pool = Map.get(config, "https://s3.example.com")

      assert Keyword.get(s3_pool, :protocols) == [:http2]
      assert Keyword.get(s3_pool[:conn_opts], :protocols) == [:http2]
    end

    test "server pool keeps its own protocols regardless of S3 config" do
      Application.put_env(:cache, :server_url, "https://tuist.dev")

      Application.put_env(:cache, :s3,
        bucket: "test-bucket",
        protocols: [:http1]
      )

      Application.put_env(:ex_aws, :s3,
        scheme: "https://",
        host: "s3.example.com",
        region: "us-east-1"
      )

      config = Pools.config()
      server_pool = Map.get(config, "https://tuist.dev")

      assert Keyword.get(server_pool, :protocols) == [:http2, :http1]
      assert Keyword.get(server_pool[:conn_opts], :protocols) == [:http2, :http1]
    end

    test "defaults S3 protocols to [:http1] when not configured" do
      Application.put_env(:cache, :server_url, "https://tuist.dev")
      Application.put_env(:cache, :s3, bucket: "test-bucket")

      Application.put_env(:ex_aws, :s3,
        scheme: "https://",
        host: "s3.example.com",
        region: "us-east-1"
      )

      config = Pools.config()
      s3_pool = Map.get(config, "https://s3.example.com")

      assert Keyword.get(s3_pool, :protocols) == [:http2, :http1]
    end
  end
end
