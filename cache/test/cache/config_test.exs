defmodule Cache.ConfigTest do
  use ExUnit.Case, async: true

  describe "cache_endpoint/0" do
    test "returns hostname extracted from node name" do
      cache_endpoint = Cache.Config.cache_endpoint()
      assert is_binary(cache_endpoint)
      refute String.contains?(cache_endpoint, "@")
    end
  end

  describe "s3_ca_cert_pem/0" do
    setup do
      original_s3_config = Application.get_env(:cache, :s3)

      on_exit(fn ->
        if original_s3_config do
          Application.put_env(:cache, :s3, original_s3_config)
        else
          Application.delete_env(:cache, :s3)
        end
      end)

      :ok
    end

    test "returns the configured PEM bundle" do
      Application.put_env(:cache, :s3, ca_cert_pem: "pem-content")

      assert Cache.Config.s3_ca_cert_pem() == "pem-content"
    end

    test "returns nil when unset or blank" do
      Application.put_env(:cache, :s3, [])
      assert Cache.Config.s3_ca_cert_pem() == nil

      Application.put_env(:cache, :s3, ca_cert_pem: "")
      assert Cache.Config.s3_ca_cert_pem() == nil
    end
  end
end
