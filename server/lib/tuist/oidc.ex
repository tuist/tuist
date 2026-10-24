defmodule Tuist.OIDC do
  @moduledoc """
  OIDC token validation for CI and workload identity providers.

  Supported providers:
  - GitHub Actions
  - CircleCI
  - Bitrise
  - Configured workload identity providers
  """

  alias Tuist.Accounts.OIDCTrustPolicy
  alias Tuist.KeyValueStore
  alias Tuist.OIDC.Workload

  @clock_skew_seconds 60
  @jwks_cache_ttl to_timeout(minute: 15)

  @github_actions_issuer "https://token.actions.githubusercontent.com"
  @github_actions_enterprise_issuer_prefix "https://token.actions.githubusercontent.com/"
  @github_actions_jwks_uri "https://token.actions.githubusercontent.com/.well-known/jwks"
  @bitrise_issuer "https://token.builds.bitrise.io"
  @circleci_issuer_prefix "https://oidc.circleci.com/org/"
  @audience "tuist"

  def claims(token, account_handle \\ nil)

  def claims(token, account_handle) when is_binary(token) and byte_size(token) <= 16_384 do
    with {:ok, issuer} <- peek_issuer(token) do
      case provider(issuer) do
        {:ok, provider} ->
          builtin_claims(token, issuer, provider)

        error ->
          if OIDCTrustPolicy.reserved_issuer?(issuer), do: error, else: Workload.claims(token, issuer, account_handle)
      end
    end
  end

  def claims(_, _), do: {:error, :invalid_token}

  defp builtin_claims(token, issuer, provider) do
    with {:ok, jwks_uri} <- jwks_uri(provider, issuer),
         {:ok, claims} <- verify(token, jwks_uri),
         :ok <- validate_audience(claims, provider) do
      identity_from_claims(claims, provider)
    end
  end

  defp peek_issuer(token) do
    case JOSE.JWT.peek_payload(token) do
      %JOSE.JWT{fields: %{"iss" => issuer}} when is_binary(issuer) and byte_size(issuer) in 1..512 -> {:ok, issuer}
      _ -> {:error, :invalid_token}
    end
  rescue
    _ -> {:error, :invalid_token}
  end

  defp provider(@github_actions_issuer), do: {:ok, :github_actions}

  # Enterprises that enable `include_enterprise_slug` get tokens scoped to their
  # own issuer, `https://token.actions.githubusercontent.com/<enterprise-slug>`.
  # They are signed by the same keys as the default issuer.
  defp provider(@github_actions_enterprise_issuer_prefix <> slug = issuer) do
    if slug != "" and not String.contains?(slug, "/") do
      {:ok, :github_actions}
    else
      {:error, :unsupported_provider, issuer}
    end
  end

  defp provider(@bitrise_issuer), do: {:ok, :bitrise}

  defp provider(@circleci_issuer_prefix <> org_id = issuer) do
    if org_id == "" do
      {:error, :unsupported_provider, issuer}
    else
      {:ok, :circleci}
    end
  end

  defp provider(issuer), do: {:error, :unsupported_provider, issuer}

  defp jwks_uri(:github_actions, _issuer), do: {:ok, @github_actions_jwks_uri}

  defp jwks_uri(:bitrise, _issuer), do: {:ok, "#{@bitrise_issuer}/.well-known/jwks"}

  defp jwks_uri(:circleci, issuer), do: {:ok, "#{issuer}/.well-known/jwks-pub.json"}

  defp identity_from_claims(claims, provider) do
    with {:ok, repository} <- repository_from_claims(claims, provider) do
      {:ok, %{repository: repository}}
    end
  end

  defp repository_from_claims(claims, :github_actions) do
    case claims["repository"] do
      nil -> {:error, :missing_repository_claim}
      repository -> {:ok, repository}
    end
  end

  defp repository_from_claims(claims, :bitrise) do
    owner = claims["repository_owner"]
    slug = claims["repository_slug"]
    repo_url = claims["repository_url"] || ""

    if owner && slug && github_repository_url?(repo_url) do
      {:ok, "#{owner}/#{slug}"}
    else
      {:error, :missing_repository_claim}
    end
  end

  defp repository_from_claims(claims, :circleci) do
    case claims["oidc.circleci.com/vcs-origin"] do
      "github.com/" <> repo -> {:ok, repo}
      _ -> {:error, :missing_repository_claim}
    end
  end

  defp github_repository_url?(url) do
    String.starts_with?(url, "https://github.com/") or
      String.starts_with?(url, "git@github.com:")
  end

  defp verify(token, jwks_uri) do
    with {:ok, kid} <- peek_kid(token),
         {:ok, jwks} <- fetch_jwks(jwks_uri),
         {:ok, claims} <- verify_with_keys(token, jwks, kid, jwks_uri),
         :ok <- validate_expiration(claims),
         :ok <- validate_not_before(claims) do
      {:ok, claims}
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

  defp fetch_jwks(jwks_uri) do
    cache_key = ["oidc", "jwks", jwks_uri]

    case KeyValueStore.get_or_update(cache_key, [ttl: @jwks_cache_ttl, locking: true, cache_errors: false], fn ->
           request_jwks(jwks_uri)
         end) do
      {:error, :jwks_fetch_failed} -> {:error, :jwks_fetch_failed, jwks_uri}
      result -> result
    end
  end

  defp request_jwks(jwks_uri) do
    case Req.get(jwks_uri, connect_options: [timeout: 10_000], redirect: false) do
      {:ok, %{status: 200, body: %{"keys" => keys} = body}} when is_list(keys) -> {:ok, body}
      _ -> {:error, :jwks_fetch_failed}
    end
  end

  defp verify_with_keys(token, jwks, kid, jwks_uri) do
    case verify_signature(token, jwks, kid) do
      {:error, :key_not_found} ->
        # Unknown key IDs are untrusted input. Coalesce and rate-bound refreshes
        # rather than allowing each invalid JWT to issue a provider request.
        result =
          KeyValueStore.get_or_update(
            ["oidc", "jwks_refresh", jwks_uri],
            [ttl: to_timeout(second: 10), locking: true],
            fn ->
              with {:ok, keys} <- request_jwks(jwks_uri) do
                KeyValueStore.put(["oidc", "jwks", jwks_uri], {:ok, keys}, ttl: @jwks_cache_ttl)
                {:ok, keys}
              end
            end
          )

        case result do
          {:ok, keys} ->
            case verify_signature(token, keys, kid) do
              {:error, :key_not_found} -> {:error, :invalid_signature}
              verified -> verified
            end

          _ ->
            {:error, :jwks_fetch_failed, jwks_uri}
        end

      result ->
        result
    end
  end

  defp verify_signature(token, %{"keys" => keys}, kid) do
    with {:ok, key} <- find_key(keys, kid),
         {true, %JOSE.JWT{fields: fields}, _jws} <-
           JOSE.JWT.verify_strict(JOSE.JWK.from_map(key), ["RS256"], token) do
      {:ok, fields}
    else
      {:error, :key_not_found} -> {:error, :key_not_found}
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

  defp validate_not_before(%{"nbf" => nbf}) when is_integer(nbf) do
    if nbf <= DateTime.to_unix(DateTime.utc_now()) + @clock_skew_seconds, do: :ok, else: {:error, :token_not_yet_valid}
  end

  defp validate_not_before(%{"nbf" => _}), do: {:error, :invalid_token}
  defp validate_not_before(_), do: :ok

  defp validate_audience(%{"aud" => @audience}, provider) when provider in [:github_actions, :bitrise] do
    :ok
  end

  defp validate_audience(%{"aud" => audiences}, provider)
       when is_list(audiences) and provider in [:github_actions, :bitrise] do
    if @audience in audiences do
      :ok
    else
      {:error, :invalid_audience}
    end
  end

  defp validate_audience(_claims, provider) when provider in [:github_actions, :bitrise] do
    {:error, :invalid_audience}
  end

  defp validate_audience(_claims, _provider), do: :ok
end
