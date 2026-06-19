defmodule Tuist.AtlasWorkloadIdentityTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.AtlasWorkloadIdentity
  alias Tuist.Environment

  setup :set_mimic_from_context

  setup do
    signer = JOSE.JWK.generate_key({:rsa, 2048})

    stub(Environment, :atlas_token_jwks, fn -> JSON.encode!(jwks(signer)) end)
    stub(Environment, :atlas_token_issuer, fn -> "https://kubernetes.default.svc.cluster.local" end)
    stub(Environment, :atlas_token_audience, fn -> "tuist-server" end)

    %{signer: signer}
  end

  test "verifies an Atlas projected ServiceAccount token", %{signer: signer} do
    token =
      token(
        %{
          "aud" => ["tuist-server"],
          "sub" => "system:serviceaccount:atlas-production:atlas",
          "kubernetes.io" => %{
            "namespace" => "atlas-production",
            "serviceaccount" => %{"name" => "atlas", "uid" => "atlas-uid"}
          }
        },
        signer
      )

    assert {:ok, %{namespace: "atlas-production", name: "atlas", uid: "atlas-uid"}} =
             AtlasWorkloadIdentity.verify(token)
  end

  test "rejects tokens for another audience", %{signer: signer} do
    token = token(%{"aud" => ["other"], "sub" => "system:serviceaccount:atlas-production:atlas"}, signer)

    assert {:error, :bad_audience} = AtlasWorkloadIdentity.verify(token)
  end

  test "rejects tokens from another issuer", %{signer: signer} do
    token =
      token(
        %{
          "iss" => "https://other-cluster.example.com",
          "aud" => ["tuist-server"],
          "sub" => "system:serviceaccount:atlas-production:atlas"
        },
        signer
      )

    assert {:error, :bad_issuer} = AtlasWorkloadIdentity.verify(token)
  end

  test "rejects expired tokens", %{signer: signer} do
    token =
      token(
        %{
          "exp" => DateTime.utc_now() |> DateTime.add(-120) |> DateTime.to_unix(),
          "aud" => ["tuist-server"],
          "sub" => "system:serviceaccount:atlas-production:atlas"
        },
        signer
      )

    assert {:error, :token_expired} = AtlasWorkloadIdentity.verify(token)
  end

  test "rejects non ServiceAccount subjects", %{signer: signer} do
    token = token(%{"aud" => ["tuist-server"], "sub" => "system:user:atlas"}, signer)

    assert {:error, :not_service_account} = AtlasWorkloadIdentity.verify(token)
  end

  test "fails closed when JWKS is not configured" do
    stub(Environment, :atlas_token_jwks, fn -> nil end)

    assert {:error, :not_configured} = AtlasWorkloadIdentity.verify("token")
  end

  test "rejects tokens signed by another key" do
    token =
      token(
        %{"aud" => ["tuist-server"], "sub" => "system:serviceaccount:atlas-production:atlas"},
        JOSE.JWK.generate_key({:rsa, 2048})
      )

    assert {:error, :invalid_signature} = AtlasWorkloadIdentity.verify(token)
  end

  defp token(claims, signer) do
    base_claims = %{
      "iss" => "https://kubernetes.default.svc.cluster.local",
      "aud" => ["tuist-server"],
      "exp" => DateTime.utc_now() |> DateTime.add(3600) |> DateTime.to_unix(),
      "nbf" => DateTime.utc_now() |> DateTime.add(-60) |> DateTime.to_unix(),
      "sub" => "system:serviceaccount:atlas-production:atlas"
    }

    jwt = JOSE.JWT.from_map(Map.merge(base_claims, claims))
    {_, token} = signer |> JOSE.JWT.sign(%{"alg" => "RS256", "kid" => "atlas-key"}, jwt) |> JOSE.JWS.compact()
    token
  end

  defp jwks(signer) do
    {_, public_jwk} = signer |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()
    %{"keys" => [Map.put(public_jwk, "kid", "atlas-key")]}
  end
end
