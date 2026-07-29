defmodule Tuist.AtlasWorkloadIdentity do
  @moduledoc """
  Verifies Atlas Kubernetes projected ServiceAccount tokens.

  Atlas runs in its own Kubernetes cluster, so Tuist cannot use its local
  TokenReview API to authenticate Atlas tokens. Instead, Tuist verifies the
  JWT signature against the pinned Atlas Kubernetes JWKS, checks the configured
  issuer and audience, and returns the ServiceAccount principal from `sub`.
  """

  alias Tuist.Environment

  @clock_skew_seconds 60

  def verify(token, policy \\ Environment.atlas_workload_identity_policy())

  def verify(token, policy) when is_binary(token) and token != "" do
    with {:ok, policy} <- normalize_policy(policy),
         {:ok, jwks} <- configured_jwks(policy),
         {:ok, kid} <- peek_kid(token),
         {:ok, claims} <- verify_signature(token, jwks, kid),
         :ok <- validate_issuer(claims, policy),
         :ok <- validate_audience(claims, policy),
         :ok <- validate_issued_at(claims),
         :ok <- validate_expiration(claims),
         :ok <- validate_not_before(claims),
         :ok <- validate_max_token_ttl(claims, policy),
         {:ok, principal} <- service_account_principal(claims),
         :ok <- validate_expected_principal(principal, policy),
         :ok <- validate_kubernetes_private_claims(claims, policy) do
      {:ok, principal}
    end
  end

  def verify(_token, _policy), do: {:error, :invalid_token}

  defp normalize_policy(policy) when is_map(policy) do
    normalized = %{
      audience: policy_value(policy, :audience),
      issuer: policy_value(policy, :issuer),
      jwks: policy_value(policy, :jwks),
      max_token_ttl_seconds: policy_value(policy, :max_token_ttl_seconds),
      namespace: policy_value(policy, :namespace),
      service_account_name: policy_value(policy, :service_account_name)
    }

    if Enum.all?(normalized, fn
         {:max_token_ttl_seconds, value} -> is_integer(value) and value > 0
         {_key, value} -> not is_nil(value) and value != ""
       end) do
      {:ok, normalized}
    else
      {:error, :not_configured}
    end
  end

  defp normalize_policy(_policy), do: {:error, :not_configured}

  defp policy_value(policy, key), do: Map.get(policy, key) || Map.get(policy, Atom.to_string(key))

  defp configured_jwks(%{jwks: jwks}) do
    case jwks do
      nil -> {:error, :not_configured}
      "" -> {:error, :not_configured}
      jwks when is_map(jwks) -> {:ok, jwks}
      jwks when is_binary(jwks) -> decode_jwks(jwks)
      _ -> {:error, :invalid_jwks}
    end
  end

  defp decode_jwks(jwks) do
    case JSON.decode(jwks) do
      {:ok, %{"keys" => keys} = decoded} when is_list(keys) -> {:ok, decoded}
      _ -> {:error, :invalid_jwks}
    end
  end

  defp peek_kid(token) do
    with [header_b64 | _] <- String.split(token, "."),
         {:ok, header_json} <- Base.url_decode64(header_b64, padding: false),
         {:ok, header} <- JSON.decode(header_json) do
      {:ok, header["kid"]}
    else
      _ -> {:error, :invalid_token}
    end
  end

  defp verify_signature(token, %{"keys" => keys}, kid) do
    with {:ok, key} <- find_key(keys, kid),
         {true, %JOSE.JWT{fields: claims}, _jws} <- JOSE.JWT.verify_strict(JOSE.JWK.from_map(key), ["RS256"], token) do
      {:ok, claims}
    else
      _ -> {:error, :invalid_signature}
    end
  end

  defp verify_signature(_token, _jwks, _kid), do: {:error, :invalid_signature}

  defp find_key([key | _], nil), do: {:ok, key}

  defp find_key(keys, kid) do
    case Enum.find(keys, &(&1["kid"] == kid)) do
      nil -> {:error, :invalid_signature}
      key -> {:ok, key}
    end
  end

  defp validate_issuer(%{"iss" => issuer}, %{issuer: expected_issuer}) do
    if issuer == expected_issuer do
      :ok
    else
      {:error, :bad_issuer}
    end
  end

  defp validate_issuer(_claims, _policy), do: {:error, :bad_issuer}

  defp validate_audience(%{"aud" => audience}, %{audience: expected_audience}) when is_binary(audience) do
    if audience == expected_audience do
      :ok
    else
      {:error, :bad_audience}
    end
  end

  defp validate_audience(%{"aud" => audiences}, %{audience: expected_audience}) when is_list(audiences) do
    if expected_audience in audiences do
      :ok
    else
      {:error, :bad_audience}
    end
  end

  defp validate_audience(_claims, _policy), do: {:error, :bad_audience}

  defp validate_issued_at(%{"iat" => issued_at}) when is_integer(issued_at) do
    if issued_at <= now() + @clock_skew_seconds do
      :ok
    else
      {:error, :token_not_yet_valid}
    end
  end

  defp validate_issued_at(_claims), do: {:error, :missing_issued_at}

  defp validate_expiration(%{"exp" => exp}) when is_integer(exp) do
    if exp > now() - @clock_skew_seconds do
      :ok
    else
      {:error, :token_expired}
    end
  end

  defp validate_expiration(_claims), do: {:error, :token_expired}

  defp validate_not_before(%{"nbf" => nbf}) when is_integer(nbf) do
    if nbf <= now() + @clock_skew_seconds do
      :ok
    else
      {:error, :token_not_yet_valid}
    end
  end

  defp validate_not_before(_claims), do: :ok

  defp validate_max_token_ttl(%{"exp" => exp, "iat" => issued_at}, %{max_token_ttl_seconds: max_token_ttl_seconds})
       when is_integer(exp) and is_integer(issued_at) do
    if exp >= issued_at and exp - issued_at <= max_token_ttl_seconds do
      :ok
    else
      {:error, :token_ttl_exceeded}
    end
  end

  defp validate_max_token_ttl(_claims, _policy), do: {:error, :token_ttl_exceeded}

  defp service_account_principal(%{"sub" => "system:serviceaccount:" <> subject} = claims) do
    case String.split(subject, ":", parts: 2) do
      [namespace, name] when namespace != "" and name != "" ->
        {:ok,
         %{
           namespace: namespace,
           name: name,
           uid: get_in(claims, ["kubernetes.io", "serviceaccount", "uid"])
         }}

      _ ->
        {:error, :not_service_account}
    end
  end

  defp service_account_principal(_claims), do: {:error, :not_service_account}

  defp validate_expected_principal(%{namespace: namespace, name: name} = principal, %{
         namespace: expected_namespace,
         service_account_name: expected_name
       }) do
    if namespace == expected_namespace and name == expected_name do
      :ok
    else
      {:error, {:wrong_principal, principal}}
    end
  end

  defp validate_kubernetes_private_claims(
         %{"kubernetes.io" => %{"namespace" => namespace, "serviceaccount" => %{"name" => service_account_name}}},
         %{namespace: expected_namespace, service_account_name: expected_service_account_name}
       ) do
    if namespace == expected_namespace and service_account_name == expected_service_account_name do
      :ok
    else
      {:error, :bad_kubernetes_claims}
    end
  end

  defp validate_kubernetes_private_claims(_claims, _policy), do: {:error, :bad_kubernetes_claims}

  defp now, do: DateTime.to_unix(DateTime.utc_now())
end
