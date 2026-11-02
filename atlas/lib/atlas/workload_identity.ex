defmodule Atlas.WorkloadIdentity do
  @moduledoc """
  Verifies Kubernetes projected ServiceAccount tokens that products running in
  other clusters present when they call Atlas.

  A product's cluster signs a short-lived token for a single Atlas audience and
  the kubelet rotates it in place, so there is no shared secret to store or
  rotate. Atlas cannot reach the caller's TokenReview API, so it verifies the
  JWT offline against the caller cluster's pinned public JWKS, then checks the
  issuer, audience, lifetime and an allowlist of ServiceAccount subjects.

  A policy is a map with `:issuer`, `:audience`, `:jwks` (JSON or a decoded
  map), `:max_token_ttl_seconds` and `:subjects`, a list of
  `"namespace:service-account"` strings.
  """

  @clock_skew_seconds 60
  # Kubernetes signs ServiceAccount tokens with RSA or ECDSA keys. Anything
  # else, including `none` and HMAC, is rejected before the key is used.
  @allowed_algorithms ["RS256", "ES256"]

  def verify(token, policy) when is_binary(token) and token != "" do
    with {:ok, policy} <- normalize_policy(policy),
         {:ok, jwks} <- decode_jwks(policy.jwks),
         {:ok, kid} <- peek_kid(token),
         {:ok, claims} <- verify_signature(token, jwks, kid),
         :ok <- validate_issuer(claims, policy),
         :ok <- validate_audience(claims, policy),
         :ok <- validate_lifetime(claims, policy),
         {:ok, principal} <- service_account_principal(claims),
         :ok <- validate_allowed_subject(principal, policy) do
      {:ok, principal}
    end
  end

  def verify(_token, _policy), do: {:error, :invalid_token}

  defp normalize_policy(%{} = policy) do
    with issuer when is_binary(issuer) and issuer != "" <- policy[:issuer],
         audience when is_binary(audience) and audience != "" <- policy[:audience],
         jwks when jwks not in [nil, ""] <- policy[:jwks],
         ttl when is_integer(ttl) and ttl > 0 <- policy[:max_token_ttl_seconds],
         [_ | _] = subjects <- policy[:subjects] do
      {:ok, %{issuer: issuer, audience: audience, jwks: jwks, max_token_ttl_seconds: ttl, subjects: subjects}}
    else
      _ -> {:error, :not_configured}
    end
  end

  defp normalize_policy(_policy), do: {:error, :not_configured}

  defp decode_jwks(%{"keys" => keys} = jwks) when is_list(keys), do: {:ok, jwks}

  defp decode_jwks(jwks) when is_binary(jwks) do
    case JSON.decode(jwks) do
      {:ok, %{"keys" => keys} = decoded} when is_list(keys) -> {:ok, decoded}
      _ -> {:error, :invalid_jwks}
    end
  end

  defp decode_jwks(_jwks), do: {:error, :invalid_jwks}

  defp peek_kid(token) do
    with [header_b64 | _] <- String.split(token, "."),
         {:ok, header_json} <- Base.url_decode64(header_b64, padding: false),
         {:ok, %{} = header} <- JSON.decode(header_json) do
      {:ok, header["kid"]}
    else
      _ -> {:error, :invalid_token}
    end
  end

  # Kubernetes always sets `kid`. Without one there is no telling which key
  # signed the token, so it is rejected rather than tried against every key.
  defp verify_signature(_token, _jwks, nil), do: {:error, :invalid_signature}

  defp verify_signature(token, %{"keys" => keys}, kid) do
    with %{} = key <- Enum.find(keys, &(&1["kid"] == kid)),
         {true, %JOSE.JWT{fields: claims}, _jws} <-
           JOSE.JWT.verify_strict(JOSE.JWK.from_map(key), @allowed_algorithms, token) do
      {:ok, claims}
    else
      _ -> {:error, :invalid_signature}
    end
  rescue
    _ -> {:error, :invalid_signature}
  end

  defp validate_issuer(%{"iss" => issuer}, %{issuer: issuer}), do: :ok
  defp validate_issuer(_claims, _policy), do: {:error, :bad_issuer}

  defp validate_audience(%{"aud" => audience}, %{audience: audience}), do: :ok

  defp validate_audience(%{"aud" => audiences}, %{audience: audience}) when is_list(audiences) do
    if audience in audiences, do: :ok, else: {:error, :bad_audience}
  end

  defp validate_audience(_claims, _policy), do: {:error, :bad_audience}

  defp validate_lifetime(%{"iat" => iat, "exp" => exp} = claims, %{max_token_ttl_seconds: max_ttl})
       when is_integer(iat) and is_integer(exp) do
    now = System.os_time(:second)
    nbf = Map.get(claims, "nbf", iat)

    cond do
      not is_integer(nbf) -> {:error, :invalid_token}
      iat > now + @clock_skew_seconds or nbf > now + @clock_skew_seconds -> {:error, :token_not_yet_valid}
      exp <= now - @clock_skew_seconds -> {:error, :token_expired}
      exp < iat or exp - iat > max_ttl -> {:error, :token_ttl_exceeded}
      true -> :ok
    end
  end

  defp validate_lifetime(_claims, _policy), do: {:error, :invalid_token}

  # The `sub` and the private `kubernetes.io` claims must name the same
  # ServiceAccount, so a token cannot borrow one identity's subject.
  defp service_account_principal(
         %{
           "sub" => "system:serviceaccount:" <> subject,
           "kubernetes.io" => %{"namespace" => namespace, "serviceaccount" => %{"name" => name} = service_account}
         } = claims
       ) do
    if subject == namespace <> ":" <> name and namespace != "" and name != "" do
      {:ok,
       %{
         namespace: namespace,
         name: name,
         uid: service_account["uid"],
         pod: get_in(claims, ["kubernetes.io", "pod", "name"])
       }}
    else
      {:error, :bad_kubernetes_claims}
    end
  end

  defp service_account_principal(_claims), do: {:error, :not_service_account}

  defp validate_allowed_subject(%{namespace: namespace, name: name} = principal, %{subjects: subjects}) do
    if (namespace <> ":" <> name) in subjects, do: :ok, else: {:error, {:wrong_principal, principal}}
  end
end
