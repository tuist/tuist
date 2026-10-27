defmodule TuistOps.ProjectAccess.TokenTest do
  use ExUnit.Case, async: true
  use Mimic

  alias TuistOps.Environment
  alias TuistOps.ProjectAccess.Grant
  alias TuistOps.ProjectAccess.Token

  setup :verify_on_exit!

  setup do
    jwk = JOSE.JWK.generate_key({:okp, :Ed25519})
    priv_pem = unwrap(JOSE.JWK.to_pem(jwk))
    pub = JOSE.JWK.from_pem(unwrap(jwk |> JOSE.JWK.to_public() |> JOSE.JWK.to_pem()))

    stub(Environment, :project_access_signing_key, fn -> priv_pem end)
    stub(Environment, :operator_grant_audience, fn -> "tuist-server" end)

    {:ok, pub: pub}
  end

  defp unwrap({_kty, pem}), do: pem
  defp unwrap(pem) when is_binary(pem), do: pem

  defp grant do
    %Grant{
      id: 42,
      requester_email: "marek@tuist.dev",
      account_handle: "acme",
      tier: "read",
      reason: "investigating a failing build",
      expires_at: DateTime.utc_now() |> DateTime.add(1800, :second) |> DateTime.truncate(:second)
    }
  end

  test "mints an EdDSA JWT the matching public key verifies", %{pub: pub} do
    token = Token.mint(grant())

    {verified?, jwt, _jws} = JOSE.JWT.verify_strict(pub, ["EdDSA"], token)
    assert verified?

    fields = jwt.fields
    assert fields["iss"] == "ops.tuist.dev"
    assert fields["aud"] == "tuist-server"
    assert fields["sub"] == "marek@tuist.dev"
    assert fields["account_handle"] == "acme"
    assert fields["tier"] == "read"
    assert fields["jti"] == "42"
    assert is_integer(fields["iat"])
    assert is_integer(fields["exp"])
    assert fields["exp"] > fields["iat"]
  end

  test "a tampered token fails verification", %{pub: pub} do
    token = Token.mint(grant())
    [header, payload, signature] = String.split(token, ".")
    tampered = Enum.join([header, payload, String.reverse(signature)], ".")

    {verified?, _jwt, _jws} = JOSE.JWT.verify_strict(pub, ["EdDSA"], tampered)
    refute verified?
  end

  test "is rejected by an EdDSA-only verifier when presented under the wrong alg allowlist", %{
    pub: pub
  } do
    token = Token.mint(grant())
    {verified?, _jwt, _jws} = JOSE.JWT.verify_strict(pub, ["none"], token)
    refute verified?
  end

  test "raises when no signing key is configured" do
    stub(Environment, :project_access_signing_key, fn -> nil end)
    assert_raise RuntimeError, fn -> Token.mint(grant()) end
  end
end
