defmodule Runner.Runner.GitHub.AuthTest do
  use ExUnit.Case, async: true

  alias Runner.Runner.GitHub.Auth

  describe "generate_jwt/4" do
    test "generates a valid JWT with RSA private key" do
      # Generate a test RSA key pair
      private_key = :public_key.generate_key({:rsa, 2048, 65537})
      pem = :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, private_key)])

      assert {:ok, jwt} = Auth.generate_jwt(pem, "runner-123", "client-uuid", "https://example.com/token")
      assert is_binary(jwt)

      # JWT should have 3 parts separated by dots
      parts = String.split(jwt, ".")
      assert length(parts) == 3
    end

    test "returns error for invalid PEM" do
      assert {:error, _} = Auth.generate_jwt("not a valid pem", "runner-123", "client-uuid", "https://example.com/token")
    end
  end

  describe "ensure_valid_token/1" do
    test "returns ok with valid token that hasn't expired" do
      credentials = %{
        access_token: "valid-token",
        token_expires_at: DateTime.utc_now() |> DateTime.add(3600, :second)
      }

      assert {:ok, ^credentials} = Auth.ensure_valid_token(credentials)
    end

    test "attempts refresh when access_token is nil" do
      credentials = %{
        runner_id: "123",
        rsa_private_key: nil,
        auth_url: "https://example.com",
        access_token: nil,
        token_expires_at: DateTime.utc_now() |> DateTime.add(3600, :second)
      }

      # Will fail because rsa_private_key is nil, but we're testing that it tries to refresh
      assert {:error, _} = Auth.ensure_valid_token(credentials)
    end
  end

  describe "auth_headers/1" do
    test "returns authorization header with bearer token" do
      credentials = %{access_token: "test-token"}

      headers = Auth.auth_headers(credentials)

      assert {"Authorization", "Bearer test-token"} in headers
    end
  end
end
