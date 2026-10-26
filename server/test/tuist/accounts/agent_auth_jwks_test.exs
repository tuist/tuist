defmodule Tuist.Accounts.AgentAuthJWKSTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts.AgentAuth
  alias Tuist.KeyValueStore
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    cache = String.to_atom("agent_jwks_test_#{System.unique_integer([:positive])}")
    start_supervised!({Cachex, [cache, []]})

    stub(KeyValueStore, :get_or_update, fn key, opts, fun ->
      if match?(["agent_auth", "jwks", _], key), do: assert(opts[:cache_errors] == false)

      Mimic.call_original(KeyValueStore, :get_or_update, [
        key,
        opts |> Keyword.put(:cache, cache) |> Keyword.put(:locking, false),
        fun
      ])
    end)

    stub(KeyValueStore, :put, fn key, value, opts ->
      Mimic.call_original(KeyValueStore, :put, [key, value, Keyword.put(opts, :cache, cache)])
    end)

    uri = "https://jwks.example.com/#{Ecto.UUID.generate()}"

    stub(Tuist.Environment, :agent_auth_trusted_providers, fn ->
      [%{"issuer" => "https://agent-provider.example.com", "jwks_uri" => uri, "client_ids" => ["test-agent-client"]}]
    end)

    user = AccountsFixtures.user_fixture()
    jwk = JOSE.JWK.generate_key({:rsa, 2048})
    {_, public} = jwk |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()
    %{uri: uri, jwks: %{"keys" => [Map.put(public, "kid", "rotated-key")]}, jwk: jwk, email: user.email}
  end

  test "transport failures and malformed successful responses are not retained", %{uri: uri, jwks: jwks} = ctx do
    expect(Req, :get, fn ^uri, _ -> {:error, :timeout} end)
    assert {:error, :invalid_signature} = register(ctx)
    expect(Req, :get, fn ^uri, _ -> {:ok, %{status: 200, body: %{"unexpected" => true}}} end)
    assert {:error, :invalid_signature} = register(ctx)
    expect(Req, :get, fn ^uri, _ -> {:ok, %{status: 200, body: jwks}} end)
    assert {:ok, _} = register(ctx)
    assert {:ok, _} = register(ctx)
  end

  test "a rotated signing key refreshes the normal cached keyset", %{uri: uri, jwks: jwks} = ctx do
    expect(Req, :get, fn ^uri, _ -> {:ok, %{status: 200, body: %{"keys" => []}}} end)
    expect(Req, :get, fn ^uri, _ -> {:ok, %{status: 200, body: jwks}} end)
    assert {:ok, _} = register(ctx)
    assert {:ok, _} = register(ctx)
  end

  test "an unknown-key wave has only one bounded forced refresh", %{uri: uri} = ctx do
    expect(Req, :get, 2, fn ^uri, _ -> {:ok, %{status: 200, body: %{"keys" => []}}} end)
    for _ <- 1..20, do: assert({:error, :invalid_key} = register(ctx))
  end

  defp register(ctx) do
    now = System.system_time(:second)

    claims = %{
      "iss" => "https://agent-provider.example.com",
      "sub" => "provider-user",
      "aud" => "http://www.example.com",
      "client_id" => "test-agent-client",
      "jti" => Ecto.UUID.generate(),
      "iat" => now,
      "exp" => now + 300,
      "email" => ctx.email,
      "email_verified" => true
    }

    {_, token} =
      ctx.jwk
      |> JOSE.JWT.sign(
        %{"alg" => "RS256", "kid" => "rotated-key", "typ" => "oauth-id-jag+jwt"},
        JOSE.JWT.from_map(claims)
      )
      |> JOSE.JWS.compact()

    AgentAuth.create_registration(%{
      registration_type: :agent_provider,
      assertion: token,
      audience: "http://www.example.com",
      requested_credential_type: :access_token
    })
  end
end
