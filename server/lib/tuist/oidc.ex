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
    case String.split(token, ".") do
      [header_b64 | _] ->
        with {:ok, header_json} <- Base.url_decode64(header_b64, padding: false),
             {:ok, header} <- Jason.decode(header_json) do
          {:ok, header["kid"]}
        else
          _ -> {:error, :invalid_token}
        end

      _ ->
        {:error, :invalid_token}
    end
  end

  defp fetch_jwks(jwks_uri) do
    cache_key = ["oidc", "jwks", jwks_uri]

    KeyValueStore.get_or_update(cache_key, [ttl: @jwks_cache_ttl, locking: false], fn ->
      case Req.get(jwks_uri) do
        {:ok, %{status: 200, body: body}} -> {:ok, body}
        _ -> {:error, :jwks_fetch_failed}
      end
    end)
  end

  defp verify_signature(token, %{"keys" => keys}, kid) do
    key =
      if kid do
        Enum.find(keys, fn k -> k["kid"] == kid end)
      else
        List.first(keys)
      end

    if key do
      jwk = JOSE.JWK.from_map(key)

      case JOSE.JWT.verify_strict(jwk, ["RS256"], token) do
        {true, %JOSE.JWT{fields: fields}, _jws} -> {:ok, fields}
        _ -> {:error, :invalid_signature}
      end
    else
      {:error, :invalid_signature}
    end
  end

  defp verify_signature(_, _, _), do: {:error, :invalid_signature}

  defp validate_expiration(%{"exp" => exp}) when is_integer(exp) do
    if exp > DateTime.to_unix(DateTime.utc_now()) do
      :ok
    else
      {:error, :token_expired}
    end
  end

  defp validate_expiration(_), do: {:error, :token_expired}
end
