defmodule TuistCommon.FinchPoolsTest do
  use ExUnit.Case, async: false

  alias TuistCommon.FinchPools

  describe "s3_pool/1" do
    test "returns {endpoint, opts} with production defaults" do
      {endpoint, opts} = FinchPools.s3_pool(endpoint: "https://s3.example.com")

      assert endpoint == "https://s3.example.com"
      assert Keyword.fetch!(opts, :size) == 500
      assert Keyword.fetch!(opts, :count) == System.schedulers_online()
      assert Keyword.fetch!(opts, :protocols) == [:http1]
      assert Keyword.fetch!(opts, :start_pool_metrics?) == true

      conn_opts = Keyword.fetch!(opts, :conn_opts)
      assert Keyword.fetch!(conn_opts, :log) == true
      assert Keyword.fetch!(conn_opts, :protocols) == [:http1]

      transport_opts = Keyword.fetch!(conn_opts, :transport_opts)
      assert Keyword.fetch!(transport_opts, :inet6) == false
      assert Keyword.fetch!(transport_opts, :verify) == :verify_peer
      assert Keyword.has_key?(transport_opts, :cacertfile)
    end

    test "honours overrides" do
      {_endpoint, opts} =
        FinchPools.s3_pool(
          endpoint: "https://minio.local:9000",
          size: 42,
          count: 3,
          protocols: [:http2, :http1],
          use_ipv6: true,
          start_pool_metrics: false
        )

      assert Keyword.fetch!(opts, :size) == 42
      assert Keyword.fetch!(opts, :count) == 3
      assert Keyword.fetch!(opts, :protocols) == [:http2, :http1]
      assert Keyword.fetch!(opts, :start_pool_metrics?) == false

      transport_opts = opts |> Keyword.fetch!(:conn_opts) |> Keyword.fetch!(:transport_opts)
      assert Keyword.fetch!(transport_opts, :inet6) == true
    end

    test "uses supplied CA bundle instead of CAStore" do
      pem = File.read!(CAStore.file_path())

      {_endpoint, opts} =
        FinchPools.s3_pool(endpoint: "https://s3.example.com", ca_cert_pem: pem)

      transport_opts = opts |> Keyword.fetch!(:conn_opts) |> Keyword.fetch!(:transport_opts)
      refute Keyword.has_key?(transport_opts, :cacertfile)

      cacerts = Keyword.fetch!(transport_opts, :cacerts)
      assert is_list(cacerts) and cacerts != []
      assert Enum.all?(cacerts, &is_binary/1)
    end

    test "raises when endpoint is missing" do
      assert_raise KeyError, fn -> FinchPools.s3_pool([]) end
    end
  end

  describe "s3_endpoint_from_ex_aws_config/0" do
    setup do
      original = Application.get_env(:ex_aws, :s3)
      on_exit(fn -> restore_s3_config(original) end)
      :ok
    end

    test "returns nil when :s3 config is missing" do
      Application.delete_env(:ex_aws, :s3)
      assert FinchPools.s3_endpoint_from_ex_aws_config() == nil
    end

    test "returns nil when host is missing" do
      Application.put_env(:ex_aws, :s3, scheme: "https://", port: 443)
      assert FinchPools.s3_endpoint_from_ex_aws_config() == nil
    end

    test "returns scheme + host when port is absent" do
      Application.put_env(:ex_aws, :s3, scheme: "https://", host: "s3.example.com")
      assert FinchPools.s3_endpoint_from_ex_aws_config() == "https://s3.example.com"
    end

    test "defaults scheme to https:// when not set" do
      Application.put_env(:ex_aws, :s3, host: "s3.example.com")
      assert FinchPools.s3_endpoint_from_ex_aws_config() == "https://s3.example.com"
    end

    test "includes port when present" do
      Application.put_env(:ex_aws, :s3,
        scheme: "http://",
        host: "localhost",
        port: 9000
      )

      assert FinchPools.s3_endpoint_from_ex_aws_config() == "http://localhost:9000"
    end
  end

  defp restore_s3_config(nil), do: Application.delete_env(:ex_aws, :s3)
  defp restore_s3_config(value), do: Application.put_env(:ex_aws, :s3, value)
end
