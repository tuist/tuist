defmodule TuistWeb.OperatorGrantTest do
  use ExUnit.Case, async: true
  use Mimic

  alias TuistWeb.OperatorGrant

  setup :verify_on_exit!

  setup do
    jwk = JOSE.JWK.generate_key({:okp, :Ed25519})
    pub_pem = jwk |> JOSE.JWK.to_public() |> JOSE.JWK.to_pem() |> unwrap()

    stub(Tuist.Environment, :operator_grant_public_key, fn -> pub_pem end)
    stub(Tuist.Environment, :operator_grant_audience, fn -> "tuist-server" end)
    stub(Tuist.Environment, :operator_grant_max_ttl_seconds, fn -> 3600 end)

    {:ok, signer: jwk}
  end

  describe "verify/1" do
    test "accepts a well-formed EdDSA grant and normalises its claims", %{signer: signer} do
      token = mint(signer, claims())

      assert {:ok, grant} = OperatorGrant.verify(token)
      assert grant.tier == :read
      assert grant.account_handle == "acme"
      assert grant.sub == "operator@tuist.dev"
      assert is_integer(grant.exp)
    end

    test "maps the admin tier to an atom", %{signer: signer} do
      token = mint(signer, claims(%{"tier" => "admin"}))
      assert {:ok, %{tier: :admin}} = OperatorGrant.verify(token)
    end

    test "rejects a token signed by a different key", %{signer: _signer} do
      other = JOSE.JWK.generate_key({:okp, :Ed25519})
      token = mint(other, claims())
      assert {:error, :invalid_signature} = OperatorGrant.verify(token)
    end

    test "rejects an alg:none token" do
      assert {:error, _} = OperatorGrant.verify(none_token(claims()))
    end

    test "rejects an HS256 token signed with a symmetric secret" do
      {_m, token} =
        "any-secret"
        |> JOSE.JWK.from_oct()
        |> JOSE.JWT.sign(%{"alg" => "HS256"}, claims())
        |> JOSE.JWS.compact()

      assert {:error, _} = OperatorGrant.verify(token)
    end

    test "rejects an expired token", %{signer: signer} do
      now = System.system_time(:second)
      token = mint(signer, claims(%{"iat" => now - 100, "exp" => now - 1}))
      assert {:error, :expired} = OperatorGrant.verify(token)
    end

    test "rejects a token whose TTL exceeds the ceiling", %{signer: signer} do
      now = System.system_time(:second)
      token = mint(signer, claims(%{"iat" => now, "exp" => now + 7200}))
      assert {:error, :ttl_too_long} = OperatorGrant.verify(token)
    end

    test "rejects a wrong audience", %{signer: signer} do
      token = mint(signer, claims(%{"aud" => "some-other-server"}))
      assert {:error, :bad_audience} = OperatorGrant.verify(token)
    end

    test "rejects a wrong issuer", %{signer: signer} do
      token = mint(signer, claims(%{"iss" => "evil.example.com"}))
      assert {:error, :bad_issuer} = OperatorGrant.verify(token)
    end

    test "rejects an unknown tier", %{signer: signer} do
      token = mint(signer, claims(%{"tier" => "superuser"}))
      assert {:error, :invalid_tier} = OperatorGrant.verify(token)
    end

    test "fails closed when no public key is configured", %{signer: signer} do
      stub(Tuist.Environment, :operator_grant_public_key, fn -> nil end)
      token = mint(signer, claims())
      assert {:error, :no_public_key} = OperatorGrant.verify(token)
    end

    test "rejects a non-binary token" do
      assert {:error, :invalid_token} = OperatorGrant.verify(nil)
    end
  end

  defp claims(overrides \\ %{}) do
    now = System.system_time(:second)

    Map.merge(
      %{
        "iss" => "ops.tuist.dev",
        "aud" => "tuist-server",
        "sub" => "operator@tuist.dev",
        "account_handle" => "acme",
        "tier" => "read",
        "reason" => "investigating",
        "jti" => "1",
        "iat" => now,
        "exp" => now + 600
      },
      overrides
    )
  end

  defp mint(signer, claims) do
    {_meta, token} = signer |> JOSE.JWT.sign(%{"alg" => "EdDSA"}, claims) |> JOSE.JWS.compact()
    token
  end

  defp none_token(claims) do
    header = %{"alg" => "none", "typ" => "JWT"} |> JSON.encode!() |> Base.url_encode64(padding: false)
    payload = claims |> JSON.encode!() |> Base.url_encode64(padding: false)
    header <> "." <> payload <> "."
  end

  defp unwrap({_kty, pem}), do: pem
  defp unwrap(pem) when is_binary(pem), do: pem
end
