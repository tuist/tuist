defmodule Tuist.WebhooksTest do
  use ExUnit.Case, async: true

  alias Tuist.Webhooks

  describe "encrypt_signing_secret/1 + decrypt_signing_secret/1" do
    test "round-trips a plaintext secret through Cloak" do
      secret = "whsec_top-secret"
      {:ok, encrypted} = Webhooks.encrypt_signing_secret(secret)

      assert is_binary(encrypted)
      refute encrypted == secret
      assert {:ok, ^secret} = Webhooks.decrypt_signing_secret(encrypted)
    end

    test "returns an error for garbage ciphertext" do
      assert {:error, :invalid_signing_secret} = Webhooks.decrypt_signing_secret("not-base64!!")
      assert {:error, :invalid_signing_secret} = Webhooks.decrypt_signing_secret(nil)
    end
  end

  describe "generate_signing_secret/0" do
    test "returns plaintext and matching encrypted ciphertext" do
      %{plaintext: plaintext, encrypted: encrypted} = Webhooks.generate_signing_secret()

      assert String.starts_with?(plaintext, "whsec_")
      assert {:ok, ^plaintext} = Webhooks.decrypt_signing_secret(encrypted)
    end

    test "each call yields a fresh secret" do
      %{plaintext: a} = Webhooks.generate_signing_secret()
      %{plaintext: b} = Webhooks.generate_signing_secret()
      assert a != b
    end
  end

  describe "valid_webhook_url?/1" do
    test "accepts HTTPS URLs with a host" do
      assert Webhooks.valid_webhook_url?("https://example.com/hook")
      assert Webhooks.valid_webhook_url?("https://api.example.com:8443/path?q=1")
    end

    test "rejects HTTP, missing hosts, and non-strings" do
      refute Webhooks.valid_webhook_url?("http://example.com/hook")
      refute Webhooks.valid_webhook_url?("https://")
      refute Webhooks.valid_webhook_url?("not a url")
      refute Webhooks.valid_webhook_url?(nil)
      refute Webhooks.valid_webhook_url?(123)
    end
  end
end
