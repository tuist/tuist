defmodule Atlas.Environments.IdentityTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.Environments.Identity

  test "only public signing material is published and workload tokens bind the owner, environment and destination" do
    key = JOSE.JWK.generate_key({:rsa, 2048})
    {_, pem} = JOSE.JWK.to_pem(key)
    stub(Identity, :config, fn -> [private_key: pem] end)
    stub(Identity, :issuer, fn -> "https://atlas.example.org" end)
    identity = %{owner_id: Ecto.UUID.generate(), environment_id: Ecto.UUID.generate(), generation: 2}
    assert {:ok, %{"keys" => [public]}} = Identity.public_keys()
    refute Map.has_key?(public, "d")
    assert public["kid"] == JOSE.JWK.thumbprint(key)
    assert {:ok, token} = Identity.token(identity, "acme", "tuist-environments")
    assert {true, %JOSE.JWT{fields: claims}, _} = JOSE.JWT.verify_strict(JOSE.JWK.from_map(public), ["RS256"], token)
    assert claims["sub"] == "user:" <> identity.owner_id
    assert claims["iss"] == "https://atlas.example.org"
    assert claims["environment_id"] == identity.environment_id
    assert claims["account_handle"] == "acme"
    assert claims["aud"] == "tuist-environments"
    assert claims["purpose"] == "atlas-environment"
    assert claims["exp"] - claims["iat"] == 300
    refute Map.has_key?(claims, "private_key")
    stub(Identity, :config, fn -> [private_key: "invalid"] end)
    assert {:error, :environment_identity_unavailable} = Identity.public_keys()
  end
end
