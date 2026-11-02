defmodule Atlas.WorkloadIdentity do
  @moduledoc """
  Verifies Kubernetes projected ServiceAccount tokens that products running in
  other clusters present when they call Atlas, so there is no shared secret.

  Atlas cannot reach the caller's TokenReview API, so it verifies the JWT
  offline against the caller cluster's pinned public JWKS. A policy is a map
  with `:issuer`, `:audience`, `:jwks` (JSON) and `:subject`, the one
  `"namespace:service-account"` allowed to call.
  """

  @clock_skew_seconds 60
  # Kubernetes' default projected token lifetime. This only bounds how long a
  # leaked token is useful; a TokenRequest for an hour or less still passes.
  @max_token_ttl_seconds 3600
  # Kubernetes signs with RSA or ECDSA keys; `none` and HMAC never verify.
  @allowed_algorithms ["RS256", "ES256"]

  def verify(token, %{issuer: issuer, audience: audience, jwks: jwks, subject: subject})
      when is_binary(issuer) and is_binary(audience) and is_binary(jwks) and is_binary(subject) do
    with true <- is_binary(token) || {:error, :missing_token},
         {:ok, claims} <- verify_signature(token, jwks),
         :ok <- validate_claims(claims, issuer, audience) do
      validate_subject(claims, subject)
    end
  end

  def verify(_token, _policy), do: {:error, :not_configured}

  defp verify_signature(token, jwks) do
    with {:ok, %{"keys" => keys}} when is_list(keys) <- JSON.decode(jwks),
         # Kubernetes always sets `kid`; a token is only tried against the key
         # it names, never against every pinned key.
         %JOSE.JWS{fields: %{"kid" => kid}} when is_binary(kid) <- JOSE.JWT.peek_protected(token),
         %{} = key <- Enum.find(keys, &(&1["kid"] == kid)),
         {true, %JOSE.JWT{fields: claims}, _jws} <-
           JOSE.JWT.verify_strict(JOSE.JWK.from_map(key), @allowed_algorithms, token) do
      {:ok, claims}
    else
      _ -> {:error, :invalid_signature}
    end
  rescue
    _ -> {:error, :invalid_signature}
  end

  defp validate_claims(%{"iss" => issuer, "aud" => audiences, "iat" => iat, "exp" => exp} = claims, issuer, audience)
       when is_integer(iat) and is_integer(exp) do
    now = System.os_time(:second)
    nbf = Map.get(claims, "nbf", iat)

    cond do
      audience not in List.wrap(audiences) -> {:error, :bad_audience}
      not is_integer(nbf) or max(iat, nbf) > now + @clock_skew_seconds -> {:error, :token_not_yet_valid}
      exp <= now - @clock_skew_seconds -> {:error, :token_expired}
      exp < iat or exp - iat > @max_token_ttl_seconds -> {:error, :token_ttl_exceeded}
      true -> :ok
    end
  end

  defp validate_claims(_claims, _issuer, _audience), do: {:error, :invalid_claims}

  # `sub` and the private `kubernetes.io` claims must both name the allowed
  # ServiceAccount, so a token cannot pair one identity's subject with another's.
  # The token must also be bound to a pod, as kubelet-projected tokens are, which
  # rejects unbound tokens such as `kubectl create token` output.
  defp validate_subject(
         %{
           "sub" => "system:serviceaccount:" <> subject,
           "kubernetes.io" => %{
             "namespace" => namespace,
             "serviceaccount" => %{"name" => name},
             "pod" => %{"name" => pod}
           }
         },
         subject
       )
       when is_binary(pod) do
    if namespace <> ":" <> name == subject, do: :ok, else: {:error, :wrong_subject}
  end

  defp validate_subject(_claims, _subject), do: {:error, :wrong_subject}
end
