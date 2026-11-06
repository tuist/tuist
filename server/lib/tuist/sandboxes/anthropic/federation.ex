defmodule Tuist.Sandboxes.Anthropic.Federation do
  @moduledoc """
  Tuist as an OpenID Connect identity provider for Anthropic Workload
  Identity Federation, so an agent environment can call Anthropic without a
  stored API key.

  Every account has its own issuer, `<app url>/oidc/accounts/<account id>`,
  serving a discovery document and a JWKS. A rule in one customer's
  Anthropic organization that trusts their issuer therefore never accepts
  tokens Tuist signs for another account, even when the rule does not check
  `sub`. Tokens are only ever signed for the account that owns the agent
  environment: `iss` and `sub` both come from the environment row.

  `credential/1` signs a fresh short-lived JWT, exchanges it at
  `POST /v1/oauth/token` (RFC 7523 `jwt-bearer`) for an `sk-ant-oat01-...`
  token and caches the token on this node until 120 seconds before it
  expires. Anthropic rejects a reused `jti`, so every exchange signs a new
  JWT. Each replica exchanges on its own; the cache is disposable.

  ## Signing key rotation

  The key is derived from Tuist's token-signing secret with a purpose label
  of its own (`AgentAuthSigningKey.derived_jwk/1`). To rotate it, add the
  next label to `@published_key_purposes`, deploy, wait for Anthropic to pick
  up the new JWKS, then move `@signing_key_purpose` to it and drop the old
  label in a later deploy. Customers using an `inline` JWKS have to paste
  the new key set into the Console before the switch.
  """

  alias Tuist.Accounts.AgentAuthSigningKey
  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.Sandboxes.AgentEnvironment
  alias Tuist.Time

  @audience "https://api.anthropic.com"
  @assertion_ttl_seconds 5 * 60
  @refresh_before_expiry_seconds 120
  @signing_key_purpose "tuist-anthropic-federation-signing-key-v1"
  @published_key_purposes [@signing_key_purpose]
  @grant_type "urn:ietf:params:oauth:grant-type:jwt-bearer"
  @authentication_history_url "https://platform.claude.com/settings/workload-identity-federation?tab=history"

  def audience, do: @audience
  def authentication_history_url, do: @authentication_history_url

  def issuer(account_id) when is_integer(account_id) do
    Environment.app_url(path: "/oidc/accounts/#{account_id}", route_type: :app)
  end

  def subject(%AgentEnvironment{account_id: account_id, id: id}), do: "account:#{account_id}:agent-environment:#{id}"

  def openid_configuration(account_id) when is_integer(account_id) do
    issuer = issuer(account_id)

    %{
      "issuer" => issuer,
      "jwks_uri" => issuer <> "/jwks.json",
      "response_types_supported" => ["id_token"],
      "subject_types_supported" => ["public"],
      "id_token_signing_alg_values_supported" => ["ES256"],
      "claims_supported" => ["iss", "sub", "aud", "iat", "nbf", "exp", "jti"]
    }
  end

  def jwks do
    keys =
      Enum.map(@published_key_purposes, fn purpose ->
        jwk = AgentAuthSigningKey.derived_jwk(purpose)
        {_, public_map} = JOSE.JWK.to_public_map(jwk)
        Map.merge(public_map, %{"kid" => JOSE.JWK.thumbprint(jwk), "alg" => "ES256", "use" => "sig"})
      end)

    %{"keys" => keys}
  end

  def federated?(%AgentEnvironment{} = agent_environment) do
    agent_environment |> ids() |> Map.values() |> Enum.all?(&(is_binary(&1) and &1 != ""))
  end

  @doc """
  The subject Tuist signs with while an account connects Claude, before
  the agent environment exists: the test exchange and creating the
  self-hosted environment. A rule whose subject prefix is
  `account:<id>:*` admits it as well as every environment of the account.
  """
  def setup_subject(account_id) when is_integer(account_id), do: "account:#{account_id}:setup"

  @doc """
  Signs a fresh identity token for the agent environment, with `iss` and
  `sub` taken from the environment's own account.
  """
  def sign(%AgentEnvironment{account_id: account_id} = agent_environment) when is_integer(account_id) do
    sign(account_id, subject(agent_environment))
  end

  defp sign(account_id, subject) do
    now = DateTime.to_unix(Time.utc_now())

    claims = %{
      "iss" => issuer(account_id),
      "sub" => subject,
      "aud" => @audience,
      "jti" => UUIDv7.generate(),
      "iat" => now,
      "nbf" => now,
      "exp" => now + @assertion_ttl_seconds
    }

    jwk = AgentAuthSigningKey.derived_jwk(@signing_key_purpose)
    header = %{"alg" => "ES256", "kid" => JOSE.JWK.thumbprint(jwk), "typ" => "JWT"}
    {_, token} = jwk |> JOSE.JWT.sign(header, JOSE.JWT.from_map(claims)) |> JOSE.JWS.compact()

    {:ok, token}
  end

  @doc """
  Exchanges a freshly signed identity token for an Anthropic access token.
  Returns `{:ok, %{token: token, expires_at: datetime}}`. A rejected
  exchange is `{:error, {:federation_rejected, %{status: status, message: message}}}`.
  """
  def exchange(%AgentEnvironment{account_id: account_id} = agent_environment) do
    exchange(account_id, subject(agent_environment), ids(agent_environment))
  end

  @doc """
  Exchanges a token signed with the account's setup subject for the given
  ids (`organization_id`, `workspace_id`, `service_account_id`,
  `federation_rule_id`), without caching it. Used to check the Console
  setup before an environment exists, and completes the Console's
  connection test.
  """
  def verify(account_id, %{} = ids) when is_integer(account_id) do
    with {:ok, %{token: token}} <- exchange(account_id, setup_subject(account_id), ids), do: {:ok, token}
  end

  defp exchange(account_id, subject, ids) do
    {:ok, assertion} = sign(account_id, subject)

    body = %{
      grant_type: @grant_type,
      assertion: assertion,
      organization_id: ids.organization_id,
      workspace_id: ids.workspace_id,
      service_account_id: ids.service_account_id,
      federation_rule_id: ids.federation_rule_id
    }

    case Req.post(Environment.anthropic_api_url() <> "/v1/oauth/token", json: body, retry: false) do
      {:ok, %Req.Response{status: 200, body: %{"access_token" => token, "expires_in" => expires_in}}}
      when is_binary(token) and is_integer(expires_in) ->
        {:ok, %{token: token, expires_at: DateTime.add(Time.utc_now(), expires_in, :second)}}

      {:ok, %Req.Response{status: status, body: body}} when status in 400..499 ->
        {:error, {:federation_rejected, %{status: status, message: error_message(body)}}}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, %{status: status, message: error_message(body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Picks the federation ids out of text a customer pastes, such as the
  exchange snippet on a federation rule's page in the Claude Console.
  Returns a map with the ids it found; missing ones are absent.
  """
  def parse_ids(text) when is_binary(text) do
    [
      organization_id: ~r/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i,
      workspace_id: ~r/\bwrkspc_[A-Za-z0-9_-]+/,
      service_account_id: ~r/\bsvac_[A-Za-z0-9_-]+/,
      federation_rule_id: ~r/\bfdrl_[A-Za-z0-9_-]+/
    ]
    |> Enum.flat_map(fn {key, pattern} ->
      case Regex.run(pattern, text) do
        [match] -> [{key, match}]
        nil -> []
      end
    end)
    |> Map.new()
  end

  @doc """
  Returns a cached Anthropic access token for the agent environment,
  exchanging a new one when there is none or it expires within
  #{@refresh_before_expiry_seconds} seconds.
  """
  def credential(%AgentEnvironment{} = agent_environment) do
    key = cache_key(agent_environment)

    case KeyValueStore.get(key) do
      %{token: token, expires_at: expires_at} ->
        if fresh?(expires_at), do: {:ok, token}, else: exchange_and_cache(agent_environment, key)

      _miss ->
        exchange_and_cache(agent_environment, key)
    end
  end

  defp exchange_and_cache(agent_environment, key) do
    with {:ok, %{token: token, expires_at: expires_at} = entry} <- exchange(agent_environment) do
      ttl_ms = DateTime.diff(expires_at, Time.utc_now(), :millisecond)
      if ttl_ms > 0, do: KeyValueStore.put(key, entry, ttl: ttl_ms)
      {:ok, token}
    end
  end

  defp fresh?(expires_at) do
    DateTime.diff(expires_at, Time.utc_now(), :second) > @refresh_before_expiry_seconds
  end

  # Node-local only (no `persist_across_deployments`), so the token never
  # leaves the replica's memory. The ids are part of the key so that changing
  # them on the environment stops using a token minted for the previous rule.
  defp cache_key(%AgentEnvironment{id: id, account_id: account_id} = agent_environment) do
    ids = ids(agent_environment)

    ["anthropic_federation", account_id, id, ids.organization_id, ids.workspace_id] ++
      [ids.service_account_id, ids.federation_rule_id]
  end

  @doc "The federation ids of an agent environment, in the shape `verify/2` takes."
  def ids(%AgentEnvironment{} = agent_environment) do
    %{
      organization_id: agent_environment.anthropic_organization_id,
      workspace_id: agent_environment.anthropic_workspace_id,
      service_account_id: agent_environment.anthropic_service_account_id,
      federation_rule_id: agent_environment.anthropic_federation_rule_id
    }
  end

  defp error_message(%{"error" => %{"message" => message}}) when is_binary(message), do: message
  defp error_message(body) when is_binary(body), do: String.slice(body, 0, 500)
  defp error_message(body), do: inspect(body)
end
