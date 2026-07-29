defmodule TuistOps.GitHub.AppTokenTest do
  use ExUnit.Case, async: true
  use Mimic

  alias TuistOps.Environment
  alias TuistOps.GitHub.AppToken

  setup :verify_on_exit!

  setup context do
    token_opts = [cache_key: {__MODULE__, context.test}]

    AppToken.clear_cache(token_opts)
    on_exit(fn -> AppToken.clear_cache(token_opts) end)

    {:ok, token_opts: token_opts}
  end

  test "mints and caches an installation token", %{token_opts: token_opts} do
    stub_credentials()
    stub_jose()

    expect(Req, :post, fn "https://api.github.com/app/installations/456/access_tokens", opts ->
      assert Enum.member?(opts[:headers], {"Authorization", "Bearer app-jwt"})

      {:ok,
       %Req.Response{
         status: 201,
         body: %{
           "token" => "installation-token",
           "expires_at" => "2099-01-01T00:00:00Z"
         }
       }}
    end)

    assert {:ok, "installation-token"} = AppToken.token(token_opts)
    assert {:ok, "installation-token"} = AppToken.token(token_opts)
  end

  test "normalizes escaped newlines in the private key", %{token_opts: token_opts} do
    stub(Environment, :github_app_id, fn -> "123" end)
    stub(Environment, :github_app_installation_id, fn -> "456" end)

    stub(Environment, :github_app_private_key, fn ->
      "-----BEGIN RSA PRIVATE KEY-----\\ntest\\n-----END RSA PRIVATE KEY-----"
    end)

    stub(JOSE.JWK, :from_pem, fn private_key ->
      assert private_key == "-----BEGIN RSA PRIVATE KEY-----\ntest\n-----END RSA PRIVATE KEY-----"
      :jwk
    end)

    stub(JOSE.JWT, :sign, fn :jwk, %{"alg" => "RS256"}, %{"iss" => "123"} -> :signed end)
    stub(JOSE.JWS, :compact, fn :signed -> {%{}, "app-jwt"} end)

    expect(Req, :post, fn _url, _opts ->
      {:ok,
       %Req.Response{
         status: 201,
         body: %{"token" => "installation-token", "expires_at" => "2099-01-01T00:00:00Z"}
       }}
    end)

    assert {:ok, "installation-token"} = AppToken.token(token_opts)
  end

  test "returns a missing environment error when credentials are incomplete", %{
    token_opts: token_opts
  } do
    stub(Environment, :github_app_id, fn -> "" end)
    stub(Environment, :github_app_installation_id, fn -> "456" end)
    stub(Environment, :github_app_private_key, fn -> "key" end)

    assert {:error, {:missing_env, "GITHUB_APP_ID"}} = AppToken.token(token_opts)
  end

  test "returns GitHub response errors without caching a token", %{token_opts: token_opts} do
    stub_credentials()
    stub_jose()

    expect(Req, :post, fn _url, _opts ->
      {:ok, %Req.Response{status: 403, body: %{"message" => "Resource not accessible"}}}
    end)

    assert {:error, {:github_status, 403, %{"message" => "Resource not accessible"}}} =
             AppToken.token(token_opts)
  end

  defp stub_credentials do
    stub(Environment, :github_app_id, fn -> "123" end)
    stub(Environment, :github_app_installation_id, fn -> "456" end)

    stub(Environment, :github_app_private_key, fn ->
      "-----BEGIN RSA PRIVATE KEY-----\ntest\n-----END RSA PRIVATE KEY-----"
    end)
  end

  defp stub_jose do
    stub(
      JOSE.JWK,
      :from_pem,
      fn "-----BEGIN RSA PRIVATE KEY-----\ntest\n-----END RSA PRIVATE KEY-----" ->
        :jwk
      end
    )

    stub(JOSE.JWT, :sign, fn :jwk, %{"alg" => "RS256"}, %{"iss" => "123"} = claims ->
      assert claims["iat"] < claims["exp"]
      :signed
    end)

    stub(JOSE.JWS, :compact, fn :signed -> {%{}, "app-jwt"} end)
  end
end
