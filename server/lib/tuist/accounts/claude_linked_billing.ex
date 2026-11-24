defmodule Tuist.Accounts.ClaudeLinkedBilling do
  @moduledoc """
  Claude Platform linked billing: an organization links its own Claude
  Platform organization to Tuist's OAuth app instead of sharing an API key,
  and Anthropic bills that organization for the requests Tuist marks with
  `billing_policy.bill_to: "user_profile"`.

  Tuist's own Claude organization owns the OAuth app and an operator service
  account. Each Tuist organization is represented there by one user profile
  (`organizations.anthropic_user_profile_id`), which the customer's
  administrator links on Anthropic's hosted approval page. Tuist stores the
  resulting connection ID, never a customer credential.

  Tuist authenticates with tokens signed by its own issuer,
  `<app url>/oidc/claude-linked-billing`, which the Claude Console registers
  through Workload Identity Federation: client assertions for
  `auth.claude.com` (PAR, token and revocation endpoints), and a
  `jwt-bearer` exchange for the operator service account's access token,
  which is cached on each node until 120 seconds before it expires.

  See https://platform.claude.com/docs/en/manage-claude/oauth-apps/organization-billing-connections
  """

  alias Tuist.Accounts.AgentAuthSigningKey
  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.Time

  @signing_key_purpose "tuist-claude-linked-billing-signing-key-v1"
  @subject "tuist:claude-linked-billing"
  @api_audience "https://api.anthropic.com"
  @assertion_ttl_seconds 5 * 60
  @refresh_before_expiry_seconds 120
  @client_assertion_type "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
  @jwt_bearer_grant "urn:ietf:params:oauth:grant-type:jwt-bearer"
  @api_version "2026-10-21"
  @billing_beta "user-profiles-billing-2026-10-01"
  @linked_platforms_url "https://platform.claude.com/linked-platforms"

  def linked_platforms_url, do: @linked_platforms_url

  def configured? do
    Environment.anthropic_linked_billing_config() |> Map.values() |> Enum.all?(&(is_binary(&1) and &1 != ""))
  end

  def issuer, do: Environment.app_url() <> "/oidc/claude-linked-billing"
  def subject, do: @subject
  def redirect_uri, do: Environment.app_url() <> "/integrations/claude/callback"

  def openid_configuration do
    %{
      "issuer" => issuer(),
      "jwks_uri" => issuer() <> "/jwks.json",
      "response_types_supported" => ["id_token"],
      "subject_types_supported" => ["public"],
      "id_token_signing_alg_values_supported" => ["ES256"],
      "claims_supported" => ["iss", "sub", "aud", "iat", "nbf", "exp", "jti"]
    }
  end

  def jwks do
    jwk = signing_key()
    {_, public_map} = JOSE.JWK.to_public_map(jwk)
    %{"keys" => [Map.merge(public_map, %{"kid" => JOSE.JWK.thumbprint(jwk), "alg" => "ES256", "use" => "sig"})]}
  end

  @doc "Creates the user profile that stands for one Tuist organization in Tuist's Claude organization."
  def create_user_profile(name, reference_id) do
    with {:ok, token} <- operator_token() do
      case Req.post(Environment.anthropic_api_url() <> "/v1/user_profiles",
             headers: [{"authorization", "Bearer " <> token}, {"anthropic-version", @api_version}],
             json: %{name: name, external_user_details: %{reference_id: reference_id}},
             retry: false
           ) do
        {:ok, %Req.Response{status: status, body: %{"id" => "uprof_" <> _ = id}}} when status in 200..201 -> {:ok, id}
        _ -> {:error, :claude_unavailable}
      end
    end
  end

  @doc """
  Pushes an authorization request for the user profile and returns the
  approval page URL with the `state` and PKCE verifier the callback needs.
  """
  def authorization_request(user_profile_id) do
    state = random_token(32)
    code_verifier = random_token(64)
    code_challenge = Base.url_encode64(:crypto.hash(:sha256, code_verifier), padding: false)
    client_id = config().client_id

    body =
      Map.merge(client_authentication(), %{
        response_type: "code",
        redirect_uri: redirect_uri(),
        scope: "billing:attribution",
        connection_type: "organization_shared",
        connection_auth_target: "platform",
        user_profile_id: user_profile_id,
        state: state,
        code_challenge: code_challenge,
        code_challenge_method: "S256"
      })

    case Req.post(Environment.anthropic_auth_url() <> "/v1/oauth/par", json: body, retry: false) do
      {:ok, %Req.Response{status: 201, body: %{"request_uri" => request_uri}}} when is_binary(request_uri) ->
        query = URI.encode_query(%{client_id: client_id, request_uri: request_uri})

        {:ok,
         %{
           url: Environment.anthropic_auth_url() <> "/oauth/authorize?" <> query,
           state: state,
           code_verifier: code_verifier
         }}

      _ ->
        {:error, :claude_unavailable}
    end
  end

  @doc "Exchanges the callback's code for the connection ID. Tuist bills through its operator account, so the connection's own tokens are discarded."
  def exchange_code(code, code_verifier) do
    body =
      Map.merge(client_authentication(), %{
        grant_type: "authorization_code",
        code: code,
        code_verifier: code_verifier,
        redirect_uri: redirect_uri()
      })

    case Req.post(Environment.anthropic_auth_url() <> "/v1/oauth/token", json: body, retry: false) do
      {:ok, %Req.Response{status: 200, body: %{"connection_id" => "ocon_" <> _ = connection_id}}} ->
        {:ok, connection_id}

      {:ok, %Req.Response{body: %{"error" => "user_profile_already_linked"}}} ->
        {:error, :already_linked}

      _ ->
        {:error, :claude_unavailable}
    end
  end

  @doc "Ends every connection of Tuist's app on the user profile."
  def unlink(user_profile_id) do
    body = Map.put(client_authentication(), :user_profile_id, user_profile_id)

    case Req.post(Environment.anthropic_auth_url() <> "/v1/oauth/revoke", json: body, retry: false) do
      {:ok, %Req.Response{status: 200}} -> :ok
      _ -> {:error, :claude_unavailable}
    end
  end

  @doc "Headers and body fields that bill a `/v1/chat/completions` request to the linked organization."
  def billing(user_profile_id) do
    with {:ok, token} <- operator_token() do
      {:ok,
       %{
         url: Environment.anthropic_api_url() <> "/v1/chat/completions",
         headers: [
           {"authorization", "Bearer " <> token},
           {"anthropic-beta", @billing_beta},
           {"anthropic-user-profile-id", user_profile_id}
         ],
         body: %{billing_policy: %{type: "billing_policy", bill_to: "user_profile"}}
       }}
    end
  end

  # The operator service account's access token. Node-local and disposable;
  # the ids are part of the key so a configuration change stops using it.
  defp operator_token do
    config = config()

    key = [
      "claude_linked_billing_operator"
      | Enum.map(~w(organization_id workspace_id service_account_id federation_rule_id)a, &config[&1])
    ]

    case KeyValueStore.get(key) do
      %{token: token, expires_at: expires_at} ->
        if DateTime.diff(expires_at, Time.utc_now(), :second) > @refresh_before_expiry_seconds,
          do: {:ok, token},
          else: exchange_operator_token(config, key)

      _ ->
        exchange_operator_token(config, key)
    end
  end

  defp exchange_operator_token(config, key) do
    body = %{
      grant_type: @jwt_bearer_grant,
      assertion: sign(@api_audience),
      organization_id: config.organization_id,
      workspace_id: config.workspace_id,
      service_account_id: config.service_account_id,
      federation_rule_id: config.federation_rule_id
    }

    case Req.post(Environment.anthropic_api_url() <> "/v1/oauth/token", json: body, retry: false) do
      {:ok, %Req.Response{status: 200, body: %{"access_token" => token, "expires_in" => expires_in}}}
      when is_binary(token) and is_integer(expires_in) and expires_in > 0 ->
        KeyValueStore.put(key, %{token: token, expires_at: DateTime.add(Time.utc_now(), expires_in, :second)},
          ttl: to_timeout(second: expires_in)
        )

        {:ok, token}

      _ ->
        {:error, :claude_unavailable}
    end
  end

  defp client_authentication do
    config = config()

    %{
      client_id: config.client_id,
      client_assertion_type: @client_assertion_type,
      client_assertion: sign(config.client_assertion_audience)
    }
  end

  # Anthropic rejects a reused `jti`, so every request signs a new assertion.
  defp sign(audience) do
    now = DateTime.to_unix(Time.utc_now())

    claims = %{
      "iss" => issuer(),
      "sub" => @subject,
      "aud" => audience,
      "jti" => UUIDv7.generate(),
      "iat" => now,
      "nbf" => now,
      "exp" => now + @assertion_ttl_seconds
    }

    jwk = signing_key()
    header = %{"alg" => "ES256", "kid" => JOSE.JWK.thumbprint(jwk), "typ" => "JWT"}
    {_, token} = jwk |> JOSE.JWT.sign(header, JOSE.JWT.from_map(claims)) |> JOSE.JWS.compact()
    token
  end

  defp signing_key, do: AgentAuthSigningKey.derived_jwk(@signing_key_purpose)
  defp config, do: Environment.anthropic_linked_billing_config()
  defp random_token(bytes), do: Base.url_encode64(:crypto.strong_rand_bytes(bytes), padding: false)
end
