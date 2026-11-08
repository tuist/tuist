defmodule Condukt.MCP.AuthTest do
  use ExUnit.Case, async: true

  alias Condukt.MCP.Auth

  describe "resolve/2 with a bearer token" do
    test "resolves an env-backed token through the injected fetch_env" do
      fetch_env = fn
        "MY_TOKEN" -> {:ok, "secret-value"}
        _other -> :error
      end

      assert {:ok, headers, %{kind: :bearer, value: "secret-value"}} =
               Auth.resolve({:bearer, {:env, "MY_TOKEN"}}, fetch_env: fetch_env)

      assert {"authorization", "Bearer secret-value"} in headers
    end

    test "returns a clear error when the env variable is missing" do
      fetch_env = fn _name -> :error end

      assert {:error, {:missing_env_secret, "MISSING"}} =
               Auth.resolve({:bearer, {:env, "MISSING"}}, fetch_env: fetch_env)
    end

    test "supports static tokens" do
      assert {:ok, headers, %{kind: :bearer}} =
               Auth.resolve({:bearer, {:static, "literal"}}, [])

      assert {"authorization", "Bearer literal"} in headers
    end
  end

  describe "resolve/2 with client_credentials" do
    test "fetches a token via the injected http function" do
      token_request = fn url, "client", "secret", "read" ->
        assert url == "https://example.com/token"
        {:ok, %{"access_token" => "abc", "token_type" => "Bearer"}}
      end

      assert {:ok, headers, state} =
               Auth.resolve(
                 {:client_credentials,
                  token_url: "https://example.com/token", client_id: "client", client_secret: "secret", scope: "read"},
                 token_request: token_request
               )

      assert {"authorization", "Bearer abc"} in headers
      assert state.kind == :client_credentials
    end

    test "surfaces a missing credential" do
      assert {:error, {:missing_credential, :client_id}} =
               Auth.resolve(
                 {:client_credentials, token_url: "https://example.com/token", client_secret: "x"},
                 []
               )
    end

    test "surfaces a missing token URL without raising" do
      assert {:error, {:missing_credential, :token_url}} =
               Auth.resolve({:client_credentials, client_id: "client", client_secret: "secret"}, [])
    end
  end

  describe "resolve/2 with no auth" do
    test "returns empty headers" do
      assert {:ok, [], %{}} = Auth.resolve(nil, [])
    end
  end
end
