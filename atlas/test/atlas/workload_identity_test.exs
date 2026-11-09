defmodule Atlas.WorkloadIdentityTest do
  use ExUnit.Case, async: true

  alias Atlas.WorkloadIdentity

  @issuer "https://kubernetes.default.svc.cluster.local"

  setup do
    signer = JOSE.JWK.generate_key({:rsa, 2048})

    policy = %{
      issuer: @issuer,
      audience: "atlas-support-ingest",
      jwks: JSON.encode!(%{"keys" => [public_key(signer, "key-1")]}),
      subject: "tuist:tuist-server"
    }

    %{policy: policy, signer: signer}
  end

  test "accepts the allowed ServiceAccount's token", %{policy: policy, signer: signer} do
    assert :ok = WorkloadIdentity.verify(token(signer, %{}), policy)
  end

  test "rejects another ServiceAccount from the same cluster", %{policy: policy, signer: signer} do
    assert {:error, :wrong_subject} =
             WorkloadIdentity.verify(token(signer, service_account_claims("tuist", "runner")), policy)
  end

  test "rejects a subject that disagrees with the Kubernetes claims", %{policy: policy, signer: signer} do
    claims =
      "tuist"
      |> service_account_claims("runner")
      |> Map.put("sub", "system:serviceaccount:tuist:tuist-server")

    assert {:error, :wrong_subject} = WorkloadIdentity.verify(token(signer, claims), policy)
  end

  test "rejects tokens that are not bound to a pod", %{policy: policy, signer: signer} do
    claims = %{"kubernetes.io" => %{"namespace" => "tuist", "serviceaccount" => %{"name" => "tuist-server"}}}

    assert {:error, :wrong_subject} = WorkloadIdentity.verify(token(signer, claims), policy)
  end

  test "rejects HMAC tokens keyed with the pinned public key", %{policy: policy, signer: signer} do
    # Algorithm confusion: an attacker who knows the public key signs with HS256.
    {_, public_pem} = signer |> JOSE.JWK.to_public() |> JOSE.JWK.to_pem()
    hmac = JOSE.JWK.from_oct(public_pem)
    forged = hmac |> JOSE.JWT.sign(%{"alg" => "HS256", "kid" => "key-1"}, claims(%{})) |> JOSE.JWS.compact() |> elem(1)

    assert {:error, :invalid_signature} = WorkloadIdentity.verify(forged, policy)
  end

  test "rejects unsigned tokens", %{policy: policy} do
    header = Base.url_encode64(~s({"alg":"none","kid":"key-1"}), padding: false)
    payload = Base.url_encode64(JSON.encode!(claims(%{})), padding: false)

    assert {:error, :invalid_signature} = WorkloadIdentity.verify(header <> "." <> payload <> ".", policy)
  end

  test "only uses the key the token names", %{policy: policy, signer: signer} do
    assert {:error, :invalid_signature} = WorkloadIdentity.verify(token(signer, %{}, "key-2"), policy)
  end

  test "rejects another issuer or audience", %{policy: policy, signer: signer} do
    assert {:error, :invalid_claims} = WorkloadIdentity.verify(token(signer, %{"iss" => "https://other"}), policy)
    assert {:error, :bad_audience} = WorkloadIdentity.verify(token(signer, %{"aud" => ["tuist-server"]}), policy)
  end

  test "enforces expiry with bounded clock skew and the maximum lifetime", %{policy: policy, signer: signer} do
    now = System.os_time(:second)

    assert :ok = WorkloadIdentity.verify(token(signer, %{"iat" => now - 3600, "exp" => now - 30}), policy)

    assert {:error, :token_expired} =
             WorkloadIdentity.verify(token(signer, %{"iat" => now - 3600, "exp" => now - 120}), policy)

    assert {:error, :token_ttl_exceeded} =
             WorkloadIdentity.verify(token(signer, %{"iat" => now, "exp" => now + 3601}), policy)
  end

  test "stays closed until fully configured", %{policy: policy, signer: signer} do
    assert {:error, :not_configured} = WorkloadIdentity.verify(token(signer, %{}), %{policy | subject: nil})
    assert {:error, :missing_token} = WorkloadIdentity.verify(nil, policy)
  end

  defp token(signer, overrides, kid \\ "key-1") do
    signer
    |> JOSE.JWT.sign(%{"alg" => "RS256", "kid" => kid}, claims(overrides))
    |> JOSE.JWS.compact()
    |> elem(1)
  end

  defp claims(overrides) do
    now = System.os_time(:second)

    %{"iss" => @issuer, "aud" => ["atlas-support-ingest"], "iat" => now, "nbf" => now, "exp" => now + 3600}
    |> Map.merge(service_account_claims("tuist", "tuist-server"))
    |> Map.merge(overrides)
  end

  defp service_account_claims(namespace, name) do
    %{
      "sub" => "system:serviceaccount:#{namespace}:#{name}",
      "kubernetes.io" => %{
        "namespace" => namespace,
        "serviceaccount" => %{"name" => name, "uid" => "uid"},
        "pod" => %{"name" => "#{name}-pod", "uid" => "pod-uid"}
      }
    }
  end

  defp public_key(signer, kid) do
    signer |> JOSE.JWK.to_public() |> JOSE.JWK.to_map() |> elem(1) |> Map.put("kid", kid)
  end
end
