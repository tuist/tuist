defmodule Cache.ConfigTest do
  use ExUnit.Case, async: true

  describe "cache_endpoint/0" do
    test "returns hostname extracted from node name" do
      cache_endpoint = Cache.Config.cache_endpoint()
      assert is_binary(cache_endpoint)
      refute String.contains?(cache_endpoint, "@")
    end
  end

  describe "cache_token_public_keys!/1" do
    test "reads one P-256 public key" do
      assert [%JOSE.JWK{}] = Cache.Config.cache_token_public_keys!(public_pem({:ec, "P-256"}))
    end

    test "reads every key in a concatenated bundle" do
      bundle = public_pem({:ec, "P-256"}) <> public_pem({:ec, "P-256"})

      assert [%JOSE.JWK{}, %JOSE.JWK{}] = Cache.Config.cache_token_public_keys!(bundle)
    end

    test "is empty when unset or blank" do
      assert Cache.Config.cache_token_public_keys!(nil) == []
      assert Cache.Config.cache_token_public_keys!("  \n") == []
    end

    test "refuses a value with no PEM block" do
      assert_raise RuntimeError, "CACHE_TOKEN_PUBLIC_KEY contains no PEM block", fn ->
        Cache.Config.cache_token_public_keys!("not a pem")
      end
    end

    test "refuses a PEM block that does not hold a key" do
      assert_raise RuntimeError, "CACHE_TOKEN_PUBLIC_KEY block 1 is not a readable public key", fn ->
        Cache.Config.cache_token_public_keys!("-----BEGIN PUBLIC KEY-----\nAAAA\n-----END PUBLIC KEY-----\n")
      end
    end

    test "refuses a key on another curve, naming the block" do
      bundle = public_pem({:ec, "P-256"}) <> public_pem({:ec, "P-384"})

      assert_raise RuntimeError, "CACHE_TOKEN_PUBLIC_KEY block 2 is on curve P-384; ES256 needs P-256", fn ->
        Cache.Config.cache_token_public_keys!(bundle)
      end
    end

    test "refuses a key of another type" do
      {_, rsa_public_key} = {:rsa, 2048} |> JOSE.JWK.generate_key() |> JOSE.JWK.to_public() |> JOSE.JWK.to_key()
      spki_pem = :public_key.pem_encode([:public_key.pem_entry_encode(:SubjectPublicKeyInfo, rsa_public_key)])

      assert_raise RuntimeError, ~r/block 1 is a RSA key; cache tokens are ES256/, fn ->
        Cache.Config.cache_token_public_keys!(spki_pem)
      end

      assert_raise RuntimeError, ~r/block 1 is a RSAPublicKey PEM; the cache takes only P-256 public keys/, fn ->
        Cache.Config.cache_token_public_keys!(public_pem({:rsa, 2048}))
      end
    end

    test "refuses a private key without echoing it" do
      {_, private_pem} = {:ec, "P-256"} |> JOSE.JWK.generate_key() |> JOSE.JWK.to_pem()

      error = assert_raise RuntimeError, fn -> Cache.Config.cache_token_public_keys!(private_pem) end

      assert error.message =~ "block 1 is a PrivateKeyInfo PEM; the cache takes only P-256 public keys"
      refute error.message =~ "-----"
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

  describe "server_ca_cert_pem/1" do
    test "returns the configured PEM bundle" do
      assert Cache.Config.server_ca_cert_pem("pem-content") == "pem-content"
    end

    test "returns nil when unset or blank" do
      assert Cache.Config.server_ca_cert_pem(nil) == nil
      assert Cache.Config.server_ca_cert_pem("") == nil
    end
  end

  defp public_pem(key_params) do
    {_, pem} = key_params |> JOSE.JWK.generate_key() |> JOSE.JWK.to_public() |> JOSE.JWK.to_pem()
    pem
  end
end
