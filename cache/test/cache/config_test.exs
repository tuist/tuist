defmodule Cache.ConfigTest do
  use ExUnit.Case, async: true

  describe "cache_endpoint/0" do
    test "returns hostname extracted from node name" do
      cache_endpoint = Cache.Config.cache_endpoint()
      assert is_binary(cache_endpoint)
      refute String.contains?(cache_endpoint, "@")
    end
  end

  describe "s3_ca_cert_pem/1" do
    test "returns the configured PEM bundle" do
      assert Cache.Config.s3_ca_cert_pem(ca_cert_pem: "pem-content") == "pem-content"
    end

    test "returns nil when unset or blank" do
      assert Cache.Config.s3_ca_cert_pem([]) == nil
      assert Cache.Config.s3_ca_cert_pem(ca_cert_pem: "") == nil
    end
  end
end
