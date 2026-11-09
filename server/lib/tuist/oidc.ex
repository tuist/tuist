defmodule Tuist.OIDC do
  @moduledoc """
  OIDC token validation for CI and workload identity providers.

  Supported providers:
  - GitHub Actions
  - CircleCI
  - Bitrise
  - Amp orbs, through account-connected Amp workspaces
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
  @amp_issuer "https://ampcode.com/api/workload-identity"
  @audience "tuist"
  # Amp recommends an audience that names the relying service.
  @amp_audience "https://tuist.dev"

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

  @doc """
  The verified claims of a GitHub Actions token minted for `audience`.
  Unlike `claims/2`, it accepts no other provider and returns every claim.
  """
  def github_actions_claims(token, audience)
      when is_binary(token) and byte_size(token) <= 16_384 and is_binary(audience) do
    with {:ok, issuer} <- peek_issuer(token),
         {:ok, :github_actions} <- provider(issuer),
         {:ok, claims} <- verify(token, @github_actions_jwks_uri),
         :ok <- audience_includes(claims, audience) do
      {:ok, claims}
    else
      {:ok, _provider} -> {:error, :unsupported_provider}
      {:error, reason, _detail} -> {:error, reason}
      error -> error
    end
  end

  def github_actions_claims(_, _), do: {:error, :invalid_token}

  @doc """
  Verifies an Amp token against the account's custom trust policies, which
  predate Amp workspace connections and also cover personal threads.
  """
  def amp_policy_claims(token, account_handle), do: Workload.claims(token, @amp_issuer, account_handle)

  defp audience_includes(%{"aud" => audience}, audience), do: :ok

  defp audience_includes(%{"aud" => audiences}, audience) when is_list(audiences) do
    if audience in audiences, do: :ok, else: {:error, :invalid_audience}
  end

  defp audience_includes(_claims, _audience), do: {:error, :invalid_audience}

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
  defp provider(@amp_issuer), do: {:ok, :amp}

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

  defp jwks_uri(:amp, _issuer), do: {:ok, amp_jwks_uri()}

  defp jwks_uri(:circleci, issuer), do: {:ok, "#{issuer}/.well-known/jwks-pub.json"}

  defp amp_jwks_uri, do: "#{@amp_issuer}/jwks.json"

  # Workspace connections follow Amp's trust guidance and accept only tokens
  # printed by `amp orb id-token`. Other tokens, and personal threads without
  # a workspace, can still match the account's custom trust policies.
  defp identity_from_claims(%{"token_use" => "exchanged"} = claims, :amp), do: {:ok, amp_identity(claims)}
  defp identity_from_claims(_claims, :amp), do: {:ok, %{amp_workspace_id: nil, amp_project_id: nil}}

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

  # Like Amp's trust recipes, the subject must name the same workspace (and
  # project) as the custom claims. A subject without a project segment, as
  # `--subject-scope workspace` mints, proves only the workspace.
  defp amp_identity(claims) do
    workspace_id = amp_uuid(claims["workspace_id"])
    project_id = amp_uuid(claims["project_id"])

    subject = if is_binary(claims["sub"]), do: claims["sub"], else: ""

    case String.split(subject, ":") do
      ["workspace", ^workspace_id, "project", ^project_id | _] ->
        %{amp_workspace_id: workspace_id, amp_project_id: project_id}

      ["workspace", ^workspace_id, "project" | _] ->
        %{amp_workspace_id: nil, amp_project_id: nil}

      ["workspace", ^workspace_id | _] ->
        %{amp_workspace_id: workspace_id, amp_project_id: nil}

      _ ->
        %{amp_workspace_id: nil, amp_project_id: nil}
    end
  end

  defp amp_uuid(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> uuid
      :error -> nil
    end
  end

  defp github_repository_url?(url) do
    String.starts_with?(url, "https://github.com/") or
      String.starts_with?(url, "git@github.com:")
  end

  defp verify(token, jwks_uri) do
    with {:ok, kid} <- peek_kid(token),
         {:ok, jwks} <- fetch_jwks(jwks_uri),
         {:ok, claims} <- verify_signature(token, jwks, kid),
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

    KeyValueStore.get_or_update(cache_key, [ttl: @jwks_cache_ttl], fn ->
      case Req.get(jwks_uri, connect_options: [timeout: 10_000], redirect: false) do
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

  defp validate_not_before(%{"nbf" => nbf}) when is_integer(nbf) do
    if nbf <= DateTime.to_unix(DateTime.utc_now()) + @clock_skew_seconds, do: :ok, else: {:error, :token_not_yet_valid}
  end

  defp validate_not_before(%{"nbf" => _}), do: {:error, :invalid_token}
  defp validate_not_before(_), do: :ok

  defp validate_audience(claims, :amp), do: audience_includes(claims, @amp_audience)

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
