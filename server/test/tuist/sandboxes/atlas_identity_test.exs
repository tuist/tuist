defmodule Tuist.Sandboxes.AtlasIdentityTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.OIDC.JWKSCache
  alias Tuist.Sandboxes.AtlasIdentity

  test "signed identities bind issuer, owner, account, environment, purpose and five-minute lifetime" do
    key = JOSE.JWK.generate_key({:rsa, 2048})
    {_, public} = key |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()
    issuer = "https://atlas.example.org"
    environment = Ecto.UUID.generate()
    owner = Ecto.UUID.generate()
    now = System.system_time(:second)

    claims = %{
      "iss" => issuer,
      "sub" => "user:" <> owner,
      "aud" => "tuist-environments",
      "iat" => now,
      "nbf" => now,
      "exp" => now + 300,
      "purpose" => "atlas-environment",
      "account_handle" => "acme",
      "environment_id" => environment
    }

    stub(AtlasIdentity, :trusts, fn -> %{"acme" => %{"issuer" => issuer, "subjects" => [claims["sub"]]}} end)

    stub(JWKSCache, :get_or_update, fn url, _fetch ->
      assert url == issuer <> "/.well-known/jwks.json"
      %{"keys" => [Map.put(public, "alg", "RS256")]}
    end)

    sign = fn fields ->
      {_, token} = key |> JOSE.JWT.sign(%{"alg" => "RS256"}, fields) |> JOSE.JWS.compact()
      token
    end

    token = sign.(claims)
    assert {:ok, identity} = AtlasIdentity.verify(token, "acme", environment)
    assert byte_size(identity) == 64
    assert {:error, :unauthorized} = AtlasIdentity.verify(token, "other", environment)
    assert {:error, :unauthorized} = AtlasIdentity.verify(token, "acme", Ecto.UUID.generate())
    assert {:error, :unauthorized} = AtlasIdentity.verify("invalid", "acme", environment)

    for {field, value} <- [
          {"iss", "https://evil.example.org"},
          {"sub", "user:" <> Ecto.UUID.generate()},
          {"aud", "tuist"},
          {"purpose", "ci"},
          {"account_handle", "other"},
          {"exp", now - 1},
          {"exp", now + 301},
          {"iat", now + 120}
        ] do
      assert {:error, :unauthorized} = AtlasIdentity.verify(sign.(Map.put(claims, field, value)), "acme", environment)
    end

    other_key = JOSE.JWK.generate_key({:rsa, 2048})
    {_, forged} = other_key |> JOSE.JWT.sign(%{"alg" => "RS256"}, claims) |> JOSE.JWS.compact()
    assert {:error, :unauthorized} = AtlasIdentity.verify(forged, "acme", environment)
  end
end
