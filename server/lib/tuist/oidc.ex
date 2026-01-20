defmodule Tuist.OIDC do
  @moduledoc """
  Generic OIDC token validation for CI providers.

  Supported providers:
  - GitHub Actions
  - CircleCI
  - Bitrise
  """

  alias Tuist.KeyValueStore

  @jwks_cache_ttl to_timeout(minute: 15)

  @github_actions_issuer "https://token.actions.githubusercontent.com"
  @bitrise_issuer "https://token.builds.bitrise.io"
  @circleci_issuer_prefix "https://oidc.circleci.com/org/"

  def claims(token) when is_binary(token) do
    with {:ok, issuer} <- peek_issuer(token),
         {:ok, jwks_uri} <- get_jwks_uri(issuer),
         {:ok, claims} <- verify(token, jwks_uri),
         {:ok, repository} <- get_repository_from_claims(claims, issuer) do
      {:ok, %{repository: repository}}
    end
  end

  def claims(_), do: {:error, :invalid_token}

  defp peek_issuer(token) do
    %JOSE.JWT{fields: %{"iss" => issuer}} = JOSE.JWT.peek_payload(token)
    {:ok, issuer}
  rescue
    _ -> {:error, :invalid_token}
  end

  defp get_jwks_uri(@github_actions_issuer) do
    {:ok, "https://token.actions.githubusercontent.com/.well-known/jwks"}
  end

  defp get_jwks_uri(@bitrise_issuer) do
    {:ok, "https://token.builds.bitrise.io/.well-known/jwks"}
  end

  defp get_jwks_uri(@circleci_issuer_prefix <> _org_id = issuer) do
    {:ok, "#{issuer}/.well-known/jwks-pub.json"}
  end

  defp get_jwks_uri(issuer), do: {:error, :unsupported_provider, issuer}

  defp get_repository_from_claims(claims, @github_actions_issuer) do
    case claims["repository"] do
      nil -> {:error, :missing_repository_claim}
      repository -> {:ok, repository}
    end
  end

  defp get_repository_from_claims(claims, @bitrise_issuer) do
    owner = claims["repository_owner"]
    slug = claims["repository_slug"]
    repo_url = claims["repository_url"] || ""

    if owner && slug && github_repository_url?(repo_url) do
      {:ok, "#{owner}/#{slug}"}
    else
      {:error, :missing_repository_claim}
    end
  end

  defp get_repository_from_claims(claims, @circleci_issuer_prefix <> _org_id) do
    case claims["oidc.circleci.com/vcs-origin"] do
      "github.com/" <> repo -> {:ok, repo}
      _ -> {:error, :missing_repository_claim}
    end
  end

  defp get_repository_from_claims(_, _), do: {:error, :missing_repository_claim}

  defp github_repository_url?(url) do
    String.starts_with?(url, "https://github.com/") or
      String.starts_with?(url, "git@github.com:")
  end

  defp verify(token, jwks_uri) do
    with {:ok, kid} <- peek_kid(token),
         {:ok, jwks} <- fetch_jwks(jwks_uri),
         {:ok, claims} <- verify_signature(token, jwks, kid),
         :ok <- validate_expiration(claims) do
      {:ok, claims}
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
        _ -> {:error, :jwks_fetch_failed, jwks_uri}
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
