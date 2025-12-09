defmodule Tuist.OIDC do
  @moduledoc """
  Generic OIDC token validation for CI providers.
  """

  alias Tuist.KeyValueStore

  @jwks_cache_ttl to_timeout(minute: 15)

  def verify(token, jwks_uri, repository_claim) do
    with {:ok, kid} <- peek_kid(token),
         {:ok, jwks} <- fetch_jwks(jwks_uri),
         {:ok, claims} <- verify_signature(token, jwks, kid),
         :ok <- validate_expiration(claims) do
      {:ok, %{repository: claims[repository_claim]}}
    end
  end

  defp peek_kid(token) do
    with [header_b64 | _] <- String.split(token, "."),
         {:ok, header_json} <- Base.url_decode64(header_b64, padding: false),
         {:ok, header} <- Jason.decode(header_json) do
      {:ok, header["kid"]}
    else
      _ -> {:error, :invalid_token}
    end
  end

  defp fetch_jwks(jwks_uri) do
    cache_key = ["oidc", "jwks", jwks_uri]

    KeyValueStore.get_or_update(cache_key, [ttl: @jwks_cache_ttl], fn ->
      case Req.get(jwks_uri) do
        {:ok, %{status: 200, body: body}} -> {:ok, body}
        _ -> {:error, :jwks_fetch_failed}
      end
    end)
  end

  defp verify_signature(token, %{"keys" => keys}, kid) do
    with {:ok, key} <- find_key(keys, kid),
         {true, %JOSE.JWT{fields: fields}, _jws} <-
           JOSE.JWT.verify_strict(JOSE.JWK.from_map(key), ["RS256"], token) do
      {:ok, fields}
    else
      _ -> {:error, :invalid_signature}
    end
  end

  defp verify_signature(_, _, _), do: {:error, :invalid_signature}

  defp find_key(keys, nil), do: {:ok, List.first(keys)}
  defp find_key(keys, kid) do
    case Enum.find(keys, &(&1["kid"] == kid)) do
      nil -> {:error, :key_not_found}
      key -> {:ok, key}
    end
  end

  defp validate_expiration(%{"exp" => exp}) when is_integer(exp) do
    if exp > DateTime.to_unix(DateTime.utc_now()) do
      :ok
    else
      {:error, :token_expired}
    end
  end

  defp validate_expiration(_), do: {:error, :token_expired}
end
