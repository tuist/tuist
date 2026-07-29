defmodule Tuist.Runners.CacheGrantTest do
  use ExUnit.Case, async: true

  import Mimic

  alias Tuist.Environment
  alias Tuist.Runners.CacheGrant

  setup :verify_on_exit!

  # Normalises JOSE's to_pem result (binary in current versions, {modules,
  # binary} in older ones) to a raw PEM string.
  defp pem(binary) when is_binary(binary), do: binary
  defp pem({_modules, binary}) when is_binary(binary), do: binary

  defp keypair do
    jwk = JOSE.JWK.generate_key({:okp, :Ed25519})
    private_pem = pem(JOSE.JWK.to_pem(jwk))
    public_pem = jwk |> JOSE.JWK.to_public() |> JOSE.JWK.to_pem() |> pem()
    {private_pem, public_pem}
  end

  test "mint/1 returns nil when no signing key is configured" do
    stub(Environment, :cache_grant_private_key, fn -> nil end)
    assert CacheGrant.mint(42) == nil
  end

  test "mint/1 returns nil for a non-integer account id" do
    assert CacheGrant.mint("42") == nil
    assert CacheGrant.mint(nil) == nil
  end

  test "mint/1 signs a verifiable, account-scoped, expiring grant" do
    {private_pem, public_pem} = keypair()
    stub(Environment, :cache_grant_private_key, fn -> private_pem end)
    stub(Environment, :cache_grant_audience, fn -> "tuist-runner-cache" end)
    stub(Environment, :cache_grant_ttl_seconds, fn -> 25_200 end)

    token = CacheGrant.mint(123)
    assert is_binary(token)

    public_jwk = JOSE.JWK.from_pem(public_pem)

    # EdDSA-strict verification — the same trust root the EE binary uses.
    assert {true, %JOSE.JWT{fields: fields}, _jws} =
             JOSE.JWT.verify_strict(public_jwk, ["EdDSA"], token)

    assert fields["scope"] == "account-123"
    assert fields["aud"] == "tuist-runner-cache"
    assert fields["iss"] == "tuist-runners"
    assert fields["exp"] - fields["iat"] == 25_200
    # Not expired.
    assert fields["exp"] > System.system_time(:second)
  end

  test "mint/1 refuses to verify under a different key (tamper/foreign key)" do
    {private_pem, _public_pem} = keypair()
    {_other_private, other_public_pem} = keypair()
    stub(Environment, :cache_grant_private_key, fn -> private_pem end)
    stub(Environment, :cache_grant_audience, fn -> "tuist-runner-cache" end)
    stub(Environment, :cache_grant_ttl_seconds, fn -> 25_200 end)

    token = CacheGrant.mint(7)
    foreign_jwk = JOSE.JWK.from_pem(other_public_pem)

    refute match?({true, _, _}, JOSE.JWT.verify_strict(foreign_jwk, ["EdDSA"], token))
  end
end
