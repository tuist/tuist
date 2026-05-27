defmodule TuistWeb.AgentAuthController do
  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Environment
  alias TuistWeb.RateLimit.AgentAuth
  alias TuistWeb.RemoteIp

  @supported_assertion_type "verified_email"
  @id_jag_assertion_type "urn:ietf:params:oauth:token-type:id-jag"
  @supported_assertion_types ["verified_email", "urn:ietf:params:oauth:token-type:id-jag"]
  @supported_credential_types ["access_token", "api_key"]

  def auth_md(conn, _params) do
    conn
    |> put_resp_content_type("text/markdown")
    |> send_resp(:ok, auth_md_document(canonical_origin()))
  end

  def register(conn, %{
        "type" => "identity_assertion",
        "assertion_type" => @id_jag_assertion_type,
        "assertion" => assertion,
        "requested_credential_type" => requested_credential_type
      })
      when requested_credential_type in @supported_credential_types do
    with {:allow, _count} <- AgentAuth.hit(conn, assertion),
         {:ok, result} <-
           Accounts.create_agent_registration(%{
             registration_type: :agent_provider,
             assertion: assertion,
             requested_credential_type: String.to_existing_atom(requested_credential_type),
             audience: canonical_origin(),
             registration_ip: RemoteIp.get(conn)
           }) do
      json(conn, %{
        registration_id: external_registration_id(result.registration),
        registration_type: "agent-provider",
        credential_type: Atom.to_string(result.credential_type),
        credential: result.credential,
        credential_expires: result.credential_expires_at,
        scopes: result.scopes
      })
    else
      {:deny, _limit} ->
        render_error(conn, :too_many_requests, "rate_limited", "Too many agent registration attempts.")

      {:error, :sso_required} ->
        render_sso_required_error(conn)

      {:error, reason}
      when reason in [
             :invalid_issuer,
             :invalid_signature,
             :expired,
             :replay_detected,
             :invalid_audience,
             :invalid_client_id,
             :missing_verified_email,
             :insufficient_user_authentication
           ] ->
        render_agent_verified_error(conn, reason)
    end
  end

  def register(conn, %{
        "type" => "identity_assertion",
        "assertion_type" => @supported_assertion_type,
        "assertion" => email,
        "requested_credential_type" => requested_credential_type
      })
      when requested_credential_type in @supported_credential_types do
    with {:allow, _count} <- AgentAuth.hit(conn, email),
         {:ok, result} <-
           Accounts.create_agent_registration(%{
             email: email,
             requested_credential_type: String.to_existing_atom(requested_credential_type),
             claim_view_url: &claim_view_url/1,
             registration_ip: RemoteIp.get(conn)
           }) do
      json(conn, %{
        registration_id: external_registration_id(result.registration),
        registration_type: "email-verification",
        claim_url: "#{canonical_origin()}/agent/auth/claim",
        claim_token: result.claim_token,
        claim_token_expires: result.claim_token_expires_at,
        post_claim_scopes: Accounts.agent_registration_scopes()
      })
    else
      {:deny, _limit} ->
        render_error(conn, :too_many_requests, "rate_limited", "Too many agent registration attempts.")

      {:error, :sso_required} ->
        render_sso_required_error(conn)

      {:error, :invalid_email} ->
        render_error(conn, :bad_request, "invalid_email", "The verified email assertion must be a valid email address.")

      {:error, :unsupported_credential_type} ->
        render_error(
          conn,
          :bad_request,
          "unsupported_credential_type",
          "Tuist only issues access tokens for auth.md registrations."
        )

      {:error, :invalid_request} ->
        render_error(conn, :bad_request, "invalid_request", "The agent registration request is invalid.")
    end
  end

  def register(conn, %{"type" => "anonymous", "requested_credential_type" => "api_key"}) do
    with {:allow, _count} <- AgentAuth.hit(conn, "anonymous"),
         {:ok, result} <-
           Accounts.create_agent_registration(%{
             registration_type: :anonymous,
             requested_credential_type: :api_key,
             registration_ip: RemoteIp.get(conn)
           }) do
      json(conn, %{
        registration_id: external_registration_id(result.registration),
        registration_type: "anonymous",
        credential_type: "api_key",
        credential: result.credential,
        credential_expires: result.credential_expires_at,
        scopes: result.scopes,
        claim_url: "#{canonical_origin()}/agent/auth/claim",
        claim_token: result.claim_token,
        claim_token_expires: result.claim_token_expires_at,
        post_claim_scopes: Accounts.agent_registration_scopes()
      })
    else
      {:deny, _limit} ->
        render_error(conn, :too_many_requests, "rate_limited", "Too many agent registration attempts.")
    end
  end

  def register(conn, %{"type" => "anonymous"}) do
    render_error(conn, :bad_request, "unsupported_credential_type", "Anonymous auth.md registrations require api_key.")
  end

  def register(conn, %{"type" => "identity_assertion", "assertion_type" => assertion_type})
      when assertion_type not in @supported_assertion_types do
    render_error(
      conn,
      :bad_request,
      "verified_email_not_enabled",
      "Tuist only accepts verified_email assertions for auth.md registrations."
    )
  end

  def register(conn, %{"requested_credential_type" => requested_credential_type})
      when requested_credential_type not in @supported_credential_types do
    render_error(
      conn,
      :bad_request,
      "unsupported_credential_type",
      "Tuist only issues access tokens for auth.md registrations."
    )
  end

  def register(conn, _params) do
    render_error(conn, :bad_request, "invalid_request", "The agent registration request is invalid.")
  end

  def claim(conn, %{"claim_token" => claim_token} = params) do
    subject = Map.get(params, "email", claim_token)

    with {:allow, _count} <- AgentAuth.hit(conn, subject),
         {:ok, result} <-
           Accounts.resend_agent_registration_claim(%{
             claim_token: claim_token,
             email: Map.get(params, "email"),
             claim_view_url: &claim_view_url/1,
             claim_requested_ip: RemoteIp.get(conn)
           }) do
      json(conn, %{
        registration_id: external_registration_id(result.registration),
        claim_attempt_id: result.registration.claim_attempt_id,
        status: "initiated",
        expires_at: result.otp_expires_at
      })
    else
      {:deny, _limit} ->
        render_error(conn, :too_many_requests, "rate_limited", "Too many claim attempts.")

      {:error, :sso_required} ->
        render_sso_required_error(conn)

      {:error, :invalid_email} ->
        render_error(conn, :bad_request, "invalid_email", "The claim email must be a valid email address.")

      {:error, :invalid_claim_token} ->
        render_error(conn, :not_found, "invalid_claim_token", "The claim token is invalid.")

      {:error, :claim_expired} ->
        render_error(conn, :gone, "claim_expired", "This registration has expired.")

      {:error, :previously_claimed} ->
        render_error(conn, :conflict, "previously_claimed", "This registration has already been claimed.")
    end
  end

  def claim(conn, _params) do
    render_error(conn, :bad_request, "invalid_request", "The claim request is invalid.")
  end

  def complete_claim(conn, %{"claim_token" => claim_token, "otp" => otp}) do
    case Accounts.complete_agent_registration_claim(%{
           claim_token: claim_token,
           otp: otp,
           claim_completed_ip: RemoteIp.get(conn)
         }) do
      {:ok, result} ->
        response = %{
          registration_id: external_registration_id(result.registration),
          status: "claimed"
        }

        response =
          if is_nil(result.credential) do
            response
          else
            Map.merge(response, %{
              credential_type: Atom.to_string(result.credential_type),
              credential: result.credential,
              credential_expires: result.credential_expires_at,
              scopes: result.scopes
            })
          end

        json(conn, response)

      {:error, reason} ->
        render_complete_claim_error(conn, reason)
    end
  end

  def complete_claim(conn, _params) do
    render_error(conn, :bad_request, "invalid_request", "The claim completion request is invalid.")
  end

  def revoke(conn, _params) do
    with {:allow, _count} <- AgentAuth.hit(conn),
         {:ok, body, _conn} <- Plug.Conn.read_body(conn),
         {:ok, result} <- Accounts.revoke_agent_registrations(body, canonical_origin()) do
      json(conn, %{revoked_count: result.revoked_count})
    else
      {:deny, _limit} ->
        render_error(conn, :too_many_requests, "rate_limited", "Too many revocation attempts.")

      {:error, reason}
      when reason in [
             :invalid_issuer,
             :invalid_signature,
             :expired,
             :replay_detected,
             :invalid_audience,
             :invalid_client_id,
             :invalid_request,
             :insufficient_user_authentication
           ] ->
        render_agent_verified_error(conn, reason)

      _ ->
        render_error(conn, :bad_request, "invalid_request", "The revocation request is invalid.")
    end
  end

  def claim_view(conn, %{"token" => token}) do
    case Accounts.get_agent_registration_claim_view(token) do
      {:ok, %{otp: otp, otp_expires_at: otp_expires_at}} ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(:ok, claim_view_html(otp, otp_expires_at))

      {:error, :otp_expired} ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(:gone, claim_error_html("Code expired", "Ask the agent to start the claim again."))

      {:error, :claim_expired} ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(:gone, claim_error_html("Registration expired", "Ask the agent to register again."))

      {:error, :previously_claimed} ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(:conflict, claim_error_html("Already claimed", "This registration has already been completed."))

      {:error, :invalid_claim_token} ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(:not_found, claim_error_html("Invalid link", "This claim link is no longer valid."))
    end
  end

  def claim_view(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(:bad_request, claim_error_html("Missing token", "This claim link is incomplete."))
  end

  defp external_registration_id(registration), do: "reg_#{registration.id}"

  # All outbound origins (audience binding for ID-JAG/logout tokens, emailed
  # claim links, and JSON `claim_url`s) come from the configured canonical
  # app URL, never from request headers — otherwise a caller could spoof
  # `X-Forwarded-Host` and have Tuist email a secret claim-view link to
  # an attacker-controlled origin.
  defp canonical_origin, do: Environment.app_url()

  defp claim_view_url(claim_view_token) do
    "#{canonical_origin()}/agent/auth/claim/view?token=#{URI.encode_www_form(claim_view_token)}"
  end

  defp render_error(conn, status, error, message) do
    conn
    |> put_status(status)
    |> json(%{error: error, message: message})
  end

  defp render_agent_verified_error(conn, reason) do
    status =
      case reason do
        :replay_detected -> :conflict
        :expired -> :gone
        _ -> :bad_request
      end

    render_error(conn, status, Atom.to_string(reason), "The agent identity assertion is invalid.")
  end

  defp render_complete_claim_error(conn, :sso_required), do: render_sso_required_error(conn)

  defp render_complete_claim_error(conn, :invalid_claim_token),
    do: render_error(conn, :not_found, "invalid_claim_token", "The claim token is invalid.")

  defp render_complete_claim_error(conn, :otp_invalid),
    do: render_error(conn, :unauthorized, "otp_invalid", "The one-time code is invalid.")

  defp render_complete_claim_error(conn, :otp_expired),
    do: render_error(conn, :gone, "otp_expired", "The one-time code has expired.")

  defp render_complete_claim_error(conn, :claim_expired),
    do: render_error(conn, :gone, "claim_expired", "This registration has expired.")

  defp render_complete_claim_error(conn, :previously_claimed),
    do: render_error(conn, :conflict, "previously_claimed", "This registration has already been claimed.")

  defp render_complete_claim_error(conn, :rate_limited),
    do: render_error(conn, :too_many_requests, "rate_limited", "Too many invalid one-time code attempts.")

  defp render_sso_required_error(conn) do
    render_error(
      conn,
      :forbidden,
      "sso_required",
      "This account is governed by an SSO-enforced organization. Sign in through your identity provider and connect the MCP server from your authenticated Tuist session."
    )
  end

  defp claim_view_html(otp, otp_expires_at) do
    expires_at = Calendar.strftime(otp_expires_at, "%Y-%m-%d %H:%M UTC")

    """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Tuist Sign-in Code</title>
        <style>
          body {
            margin: 0;
            background: #f5f3ee;
            color: #171717;
            font-family: "Helvetica Neue", Arial, sans-serif;
          }
          main {
            max-width: 540px;
            margin: 72px auto;
            padding: 40px 32px;
            background: #ffffff;
            border: 1px solid #e5e0d6;
            border-radius: 20px;
            box-shadow: 0 18px 60px rgba(23, 23, 23, 0.08);
          }
          h1 {
            margin: 0 0 12px;
            font-size: 32px;
            line-height: 1.1;
          }
          p {
            margin: 0 0 16px;
            color: #4b5563;
            line-height: 1.6;
          }
          .otp {
            margin: 28px 0;
            padding: 24px;
            border-radius: 16px;
            background: #171717;
            color: #f9fafb;
            font-size: 48px;
            font-weight: 700;
            letter-spacing: 0.3em;
            text-align: center;
          }
          .meta {
            font-size: 14px;
            color: #6b7280;
          }
        </style>
      </head>
      <body>
        <main>
          <h1>Your Tuist sign-in code</h1>
          <p>Read this six-digit code back to the agent that requested access.</p>
          <div class="otp">#{otp}</div>
          <p class="meta">This code expires at #{expires_at}.</p>
          <p class="meta">If you did not ask an agent to connect to Tuist, close this page.</p>
        </main>
      </body>
    </html>
    """
  end

  defp claim_error_html(title, message) do
    """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>#{title}</title>
        <style>
          body {
            margin: 0;
            background: #f5f3ee;
            color: #171717;
            font-family: "Helvetica Neue", Arial, sans-serif;
          }
          main {
            max-width: 540px;
            margin: 72px auto;
            padding: 40px 32px;
            background: #ffffff;
            border: 1px solid #e5e0d6;
            border-radius: 20px;
            box-shadow: 0 18px 60px rgba(23, 23, 23, 0.08);
          }
          h1 {
            margin: 0 0 12px;
            font-size: 32px;
            line-height: 1.1;
          }
          p {
            margin: 0;
            color: #4b5563;
            line-height: 1.6;
          }
        </style>
      </head>
      <body>
        <main>
          <h1>#{title}</h1>
          <p>#{message}</p>
        </main>
      </body>
    </html>
    """
  end

  defp auth_md_document(origin) do
    """
    # auth.md

    Tuist supports agent registration for the hosted MCP server at `#{origin}/mcp`.
    The protected resource is `#{origin}/mcp` and the authorization server is `#{origin}`.
    Tuist supports agent-verified ID-JAG, user-claimed anonymous start, and user-claimed email-required registration.

    ## Discover

    Start from a `401 Unauthorized` response from `#{origin}/mcp`:

    ```http
    WWW-Authenticate: Bearer resource_metadata="#{origin}/.well-known/oauth-protected-resource/mcp"
    ```

    Fetch the Protected Resource Metadata:

    - `#{origin}/.well-known/oauth-protected-resource/mcp`
    - Read `resource`, `resource_name`, `authorization_servers`, `scopes_supported`, and `bearer_methods_supported`.

    Then fetch the Authorization Server metadata:

    - `#{origin}/.well-known/oauth-authorization-server`
    - Read the `agent_auth` block:
      - `skill`: `https://workos.com/auth.md`
      - `register_uri`: `#{origin}/agent/auth`
      - `claim_uri`: `#{origin}/agent/auth/claim`
      - `revocation_uri`: `#{origin}/agent/auth/revoke`
      - `identity_types_supported`: `["anonymous", "identity_assertion"]`
      - `anonymous.credential_types_supported`: `["api_key"]`
      - `identity_assertion.assertion_types_supported`: `["verified_email", "urn:ietf:params:oauth:token-type:id-jag"]`
      - `identity_assertion.credential_types_supported`: `["access_token", "api_key"]`

    The Protected Resource Metadata is authoritative if it differs from this file.

    ## Pick a method

    Tuist supports these auth.md registration shapes:

    - Agent verified: `type: identity_assertion`, `assertion_type: urn:ietf:params:oauth:token-type:id-jag`, `requested_credential_type: access_token | api_key`.
    - User claimed anonymous start: `type: anonymous`, `requested_credential_type: api_key`.
    - User claimed email required: `type: identity_assertion`, `assertion_type: verified_email`, `requested_credential_type: access_token | api_key`.

    Tuist does not accept:

    - Anonymous `access_token` registration, because anonymous credentials must be upgradable in place after claim.
    - ID-JAG assertions from issuers that are not configured in Tuist's trusted provider list.

    Supported post-claim scope:

    - `mcp`: access to the Tuist MCP server using the user's normal Tuist permissions.

    ## Agent verified registration

    Send a provider-signed ID-JAG with audience `#{origin}`:

    ```http
    POST #{origin}/agent/auth
    Content-Type: application/json
    ```

    ```json
    {
      "type": "identity_assertion",
      "assertion_type": "urn:ietf:params:oauth:token-type:id-jag",
      "assertion": "eyJhbGciOi...",
      "requested_credential_type": "access_token"
    }
    ```

    Success returns a credential synchronously:

    ```json
    {
      "registration_id": "reg_...",
      "registration_type": "agent-provider",
      "credential_type": "access_token",
      "credential": "<token>",
      "credential_expires": "2026-05-22T13:00:00Z",
      "scopes": ["mcp"]
    }
    ```

    For `requested_credential_type: api_key`, `credential_expires` is `null`.

    ## Anonymous start registration

    Anonymous start issues an API key immediately under the MCP scope and returns a claim token that can later bind the key to the user.

    ```http
    POST #{origin}/agent/auth
    Content-Type: application/json
    ```

    ```json
    {
      "type": "anonymous",
      "requested_credential_type": "api_key"
    }
    ```

    ```json
    {
      "registration_id": "reg_...",
      "registration_type": "anonymous",
      "credential_type": "api_key",
      "credential": "<api-key>",
      "credential_expires": null,
      "scopes": ["mcp"],
      "claim_url": "#{origin}/agent/auth/claim",
      "claim_token": "clm_...",
      "claim_token_expires": "2026-05-22T12:34:56Z",
      "post_claim_scopes": ["mcp"]
    }
    ```

    ## Email-required registration

    Register with the user's verified email. Tuist emails a one-time claim link during this call and does not issue a credential yet.

    ```http
    POST #{origin}/agent/auth
    Content-Type: application/json
    ```

    ```json
    {
      "type": "identity_assertion",
      "assertion_type": "verified_email",
      "assertion": "user@example.com",
      "requested_credential_type": "access_token"
    }
    ```

    ```json
    {
      "registration_id": "reg_...",
      "registration_type": "email-verification",
      "claim_url": "#{origin}/agent/auth/claim",
      "claim_token": "clm_...",
      "claim_token_expires": "2026-05-22T12:34:56Z",
      "post_claim_scopes": ["mcp"]
    }
    ```

    `requested_credential_type` may be `access_token` or `api_key`.

    ## Claim ceremony

    ### 4a. Trigger the claim email

    Anonymous registrations call this endpoint to start the email claim. Email-required registrations may call it to re-send the claim email while the registration is still pending:

    ```http
    POST #{origin}/agent/auth/claim
    Content-Type: application/json
    ```

    ```json
    {
      "claim_token": "clm_...",
      "email": "user@example.com"
    }
    ```

    ```json
    {
      "registration_id": "reg_...",
      "claim_attempt_id": "...",
      "status": "initiated",
      "expires_at": "2026-05-22T12:10:00Z"
    }
    ```

    ### 4b. Wait for the OTP

    Ask the user to open the claim link from the Tuist email and read the six-digit OTP back to the agent.

    ### 4c. Submit the OTP

    ```http
    POST #{origin}/agent/auth/claim/complete
    Content-Type: application/json
    ```

    ```json
    {
      "claim_token": "clm_...",
      "otp": "123456"
    }
    ```

    ```json
    {
      "registration_id": "reg_...",
      "status": "claimed",
      "credential_type": "access_token",
      "credential": "<token>",
      "credential_expires": "2026-05-22T13:00:00Z",
      "scopes": ["mcp"]
    }
    ```

    ## Use the credential

    Present the returned credential as a bearer token when calling the MCP server:

    ```http
    Authorization: Bearer <credential>
    ```

    Use it against `#{origin}/mcp`.
    Tuist does not issue refresh tokens for auth.md registrations. If the token expires, is revoked, or `#{origin}/mcp` returns `401`, discard the credential and restart from discovery.

    ## Errors

    | Error | Endpoint | Meaning | Agent action |
    | --- | --- | --- | --- |
    | `verified_email_not_enabled` | `POST /agent/auth` | Unsupported `assertion_type`. | Use `verified_email`, ID-JAG, or stop. |
    | `unsupported_credential_type` | `POST /agent/auth` | Unsupported credential type. | Request `access_token` or `api_key`; anonymous start requires `api_key`. |
    | `invalid_issuer` | `POST /agent/auth`, `POST /agent/auth/revoke` | ID-JAG issuer is not trusted. | Use a configured provider. |
    | `invalid_signature` | `POST /agent/auth`, `POST /agent/auth/revoke` | The assertion signature could not be verified. | Request a fresh assertion. |
    | `invalid_audience` | `POST /agent/auth`, `POST /agent/auth/revoke` | The assertion audience does not match `#{origin}`. | Request an assertion for this audience. |
    | `invalid_client_id` | `POST /agent/auth`, `POST /agent/auth/revoke` | The client id is not accepted for the trusted provider. | Use a configured client. |
    | `missing_verified_email` | `POST /agent/auth` | The ID-JAG has no verified email. | Ask the provider for a verified email assertion. |
    | `replay_detected` | `POST /agent/auth`, `POST /agent/auth/revoke` | The assertion `jti` was already used. | Request a fresh assertion. |
    | `invalid_email` | `POST /agent/auth` | The email assertion is invalid. | Ask for a valid email and retry. |
    | `rate_limited` | `POST /agent/auth`, `POST /agent/auth/claim`, `POST /agent/auth/claim/complete` | Too many attempts. | Back off and retry later. |
    | `invalid_claim_token` | `POST /agent/auth/claim`, `POST /agent/auth/claim/complete` | The claim token is unknown. | Restart registration. |
    | `otp_invalid` | `POST /agent/auth/claim/complete` | The OTP does not match. | Ask the user for the latest OTP and retry carefully. |
    | `otp_expired` | `POST /agent/auth/claim/complete` | The OTP expired. | Re-send the claim email or restart registration. |
    | `claim_expired` | `POST /agent/auth/claim`, `POST /agent/auth/claim/complete` | The pending registration expired. | Restart registration. |
    | `previously_claimed` | `POST /agent/auth/claim`, `POST /agent/auth/claim/complete` | The registration was already completed. | Stop using the claim token and reuse the issued credential if available. |
    | `sso_required` | `POST /agent/auth`, `POST /agent/auth/claim`, `POST /agent/auth/claim/complete` | The target account is governed by an SSO-enforced organization. | Ask the user to sign in via their identity provider and connect the MCP server from their authenticated Tuist session. |

    ## SSO-enforced accounts

    Tuist refuses to mint MCP credentials through auth.md when the target email belongs to an organization that enforces SSO. Mailbox proof and trusted agent-provider assertions both bypass the organization's identity provider, so the user must instead sign in via the configured IdP and connect the MCP server from their authenticated Tuist session. The auth.md flow returns `sso_required` (HTTP 403) at every step that would otherwise bind a credential to such an account.

    ## Revocation

    Agent providers revoke ID-JAG credentials by sending a signed logout token:

    ```http
    POST #{origin}/agent/auth/revoke
    Content-Type: application/logout+jwt
    ```

    The logout token must contain the WorkOS identity assertion revoked event and the same `iss`, `sub`, and `aud` tuple used for registration.

    ## Service information

    - Pricing: `https://tuist.dev/pricing`
    - Terms of service: `https://tuist.dev/terms`
    - Privacy policy: `https://tuist.dev/privacy`
    - Contact: `mailto:contact@tuist.dev`
    """
  end
end
