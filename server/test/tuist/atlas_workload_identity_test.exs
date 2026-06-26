defmodule Tuist.AtlasWorkloadIdentityTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.AtlasWorkloadIdentity

  setup :set_mimic_from_context

  setup do
    signer = JOSE.JWK.generate_key({:rsa, 2048})

    policy = %{
      audience: "tuist-server",
      issuer: "https://kubernetes.default.svc.cluster.local",
      jwks: JSON.encode!(jwks(signer)),
      max_token_ttl_seconds: 3600,
      namespace: "atlas-production",
      service_account_name: "atlas"
    }

    %{policy: policy, signer: signer}
  end

  test "verifies an Atlas projected ServiceAccount token", %{policy: policy, signer: signer} do
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
             AtlasWorkloadIdentity.verify(token, policy)
  end

  test "rejects tokens for another audience", %{policy: policy, signer: signer} do
    token = token(%{"aud" => ["other"], "sub" => "system:serviceaccount:atlas-production:atlas"}, signer)

    assert {:error, :bad_audience} = AtlasWorkloadIdentity.verify(token, policy)
  end

  test "rejects tokens from another issuer", %{policy: policy, signer: signer} do
    token =
      token(
        %{
          "iss" => "https://other-cluster.example.com",
          "aud" => ["tuist-server"],
          "sub" => "system:serviceaccount:atlas-production:atlas"
        },
        signer
      )

    assert {:error, :bad_issuer} = AtlasWorkloadIdentity.verify(token, policy)
  end

  test "rejects expired tokens", %{policy: policy, signer: signer} do
    token =
      token(
        %{
          "exp" => DateTime.utc_now() |> DateTime.add(-120) |> DateTime.to_unix(),
          "aud" => ["tuist-server"],
          "sub" => "system:serviceaccount:atlas-production:atlas"
        },
        signer
      )

    assert {:error, :token_expired} = AtlasWorkloadIdentity.verify(token, policy)
  end

  test "rejects tokens without an issued-at claim", %{policy: policy, signer: signer} do
    token =
      %{"iat" => nil}
      |> token(signer)
      |> drop_claim("iat", signer)

    assert {:error, :missing_issued_at} = AtlasWorkloadIdentity.verify(token, policy)
  end

  test "rejects tokens whose lifetime exceeds the policy", %{policy: policy, signer: signer} do
    issued_at = DateTime.to_unix(DateTime.utc_now())

    token =
      token(
        %{
          "iat" => issued_at,
          "exp" => issued_at + policy.max_token_ttl_seconds + 1,
          "aud" => ["tuist-server"],
          "sub" => "system:serviceaccount:atlas-production:atlas"
        },
        signer
      )

    assert {:error, :token_ttl_exceeded} = AtlasWorkloadIdentity.verify(token, policy)
  end

  test "rejects non ServiceAccount subjects", %{policy: policy, signer: signer} do
    token = token(%{"aud" => ["tuist-server"], "sub" => "system:user:atlas"}, signer)

    assert {:error, :not_service_account} = AtlasWorkloadIdentity.verify(token, policy)
  end

  test "rejects tokens for another ServiceAccount", %{policy: policy, signer: signer} do
    token =
      token(
        %{
          "aud" => ["tuist-server"],
          "sub" => "system:serviceaccount:other:atlas",
          "kubernetes.io" => %{
            "namespace" => "other",
            "serviceaccount" => %{"name" => "atlas", "uid" => "atlas-uid"}
          }
        },
        signer
      )

    assert {:error, {:wrong_principal, %{namespace: "other", name: "atlas"}}} =
             AtlasWorkloadIdentity.verify(token, policy)
  end

  test "rejects tokens whose Kubernetes private claims do not match the subject", %{policy: policy, signer: signer} do
    token =
      token(
        %{
          "aud" => ["tuist-server"],
          "sub" => "system:serviceaccount:atlas-production:atlas",
          "kubernetes.io" => %{
            "namespace" => "atlas-production",
            "serviceaccount" => %{"name" => "other", "uid" => "atlas-uid"}
          }
        },
        signer
      )

    assert {:error, :bad_kubernetes_claims} = AtlasWorkloadIdentity.verify(token, policy)
  end

  test "fails closed when JWKS is not configured", %{policy: policy} do
    policy = %{policy | jwks: nil}

    assert {:error, :not_configured} = AtlasWorkloadIdentity.verify("token", policy)
  end

  test "rejects tokens signed by another key", %{policy: policy} do
    token =
      token(
        %{"aud" => ["tuist-server"], "sub" => "system:serviceaccount:atlas-production:atlas"},
        JOSE.JWK.generate_key({:rsa, 2048})
      )

    assert {:error, :invalid_signature} = AtlasWorkloadIdentity.verify(token, policy)
  end

  defp token(claims, signer) do
    now = DateTime.to_unix(DateTime.utc_now())

    base_claims = %{
      "iss" => "https://kubernetes.default.svc.cluster.local",
      "aud" => ["tuist-server"],
      "exp" => now + 3600,
      "iat" => now,
      "nbf" => now - 60,
      "sub" => "system:serviceaccount:atlas-production:atlas",
      "kubernetes.io" => %{
        "namespace" => "atlas-production",
        "serviceaccount" => %{"name" => "atlas", "uid" => "atlas-uid"}
      }
    }

    jwt = JOSE.JWT.from_map(Map.merge(base_claims, claims))
    {_, token} = signer |> JOSE.JWT.sign(%{"alg" => "RS256", "kid" => "atlas-key"}, jwt) |> JOSE.JWS.compact()
    token
  end

  defp drop_claim(token, claim, signer) do
    [_header, payload, _signature] = String.split(token, ".")
    {:ok, payload_json} = Base.url_decode64(payload, padding: false)
    {:ok, claims} = JSON.decode(payload_json)

    claims
    |> Map.delete(claim)
    |> JOSE.JWT.from_map()
    |> then(fn jwt ->
      {_, token} = signer |> JOSE.JWT.sign(%{"alg" => "RS256", "kid" => "atlas-key"}, jwt) |> JOSE.JWS.compact()
      token
    end)
  end

  defp jwks(signer) do
    {_, public_jwk} = signer |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()
    %{"keys" => [Map.put(public_jwk, "kid", "atlas-key")]}
  end
end
