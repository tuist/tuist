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

  def verify(token) when is_binary(token) and token != "" do
    with {:ok, jwks} <- configured_jwks(),
         {:ok, kid} <- peek_kid(token),
         {:ok, claims} <- verify_signature(token, jwks, kid),
         :ok <- validate_issuer(claims),
         :ok <- validate_audience(claims),
         :ok <- validate_expiration(claims),
         :ok <- validate_not_before(claims) do
      service_account_principal(claims)
    end
  end

  def verify(_token), do: {:error, :invalid_token}

  defp configured_jwks do
    case Environment.atlas_token_jwks() do
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

  defp validate_issuer(%{"iss" => issuer}) do
    if issuer == Environment.atlas_token_issuer() do
      :ok
    else
      {:error, :bad_issuer}
    end
  end

  defp validate_issuer(_claims), do: {:error, :bad_issuer}

  defp validate_audience(%{"aud" => audience}) when is_binary(audience) do
    if audience == Environment.atlas_token_audience() do
      :ok
    else
      {:error, :bad_audience}
    end
  end

  defp validate_audience(%{"aud" => audiences}) when is_list(audiences) do
    if Environment.atlas_token_audience() in audiences do
      :ok
    else
      {:error, :bad_audience}
    end
  end

  defp validate_audience(_claims), do: {:error, :bad_audience}

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

  defp now, do: DateTime.to_unix(DateTime.utc_now())
end
