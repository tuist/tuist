defmodule TuistWeb.AgentAuthDocument do
  @moduledoc false

  def render(origin) do
    """
    # auth.md

    Tuist implements the current [WorkOS auth.md protocol](https://workos.com/auth-md) for the
    [Model Context Protocol](https://modelcontextprotocol.io) server at `#{origin}/mcp`.
    Follow the discovered endpoints and the sequence below. Registration returns a signed identity
    assertion, not an access token. Exchange that assertion at the discovered token endpoint before
    calling the Model Context Protocol server.

    Prefer anonymous registration when no trusted provider identity is already available. It lets
    you inspect Tuist's agent capabilities without sending user identity. Start the browser claim
    ceremony only when a user-bound operation requires it.

    Never guess or infer the user's Tuist email address. Before sending a `service_auth` request or
    starting an anonymous claim, ask the user to confirm the exact address explicitly. Git configuration,
    environment variables, provider profiles, and previous sessions are not confirmation.

    ## 1. Discover

    A `401 Unauthorized` response from `#{origin}/mcp` includes:

    ```http
    WWW-Authenticate: Bearer resource_metadata="#{origin}/.well-known/oauth-protected-resource/mcp"
    ```

    Fetch that Protected Resource Metadata document, then fetch the first authorization server's
    `/.well-known/oauth-authorization-server` document. The authorization metadata advertises:

    - `token_endpoint`: `#{origin}/oauth2/token`
    - `revocation_endpoint`: `#{origin}/oauth2/revoke`
    - `agent_auth.skill`: this document
    - `agent_auth.identity_endpoint`: `#{origin}/agent/identity`
    - `agent_auth.claim_endpoint`: `#{origin}/agent/identity/claim`
    - `agent_auth.events_endpoint`: `#{origin}/agent/event/notify`
    - `agent_auth.identity_types_supported`: `anonymous`, `identity_assertion`, and `service_auth`

    The protected resource is `#{origin}/mcp`; use it as the `resource` parameter during token exchange.
    The supported scope is `mcp`. Before claim, that scope can discover Tuist's agent capabilities and
    read public integration guidance. After claim, it can act with the confirming user's Tuist permissions,
    subject to each tool's own authorization checks.

    ## 2. Pick a registration method

    1. If your provider can mint a fresh, audience-bound
       [Identity Assertion Authorization Grant](https://datatracker.ietf.org/doc/draft-ietf-oauth-identity-assertion-authz-grant/),
       confirm that `identity_assertion.assertion_types_supported` contains its assertion type, then use
       `identity_assertion` with assertion type `urn:ietf:params:oauth:token-type:id-jag`.
    2. If the user has explicitly confirmed their Tuist email address, use `service_auth`.
    3. Otherwise, use `anonymous`.

    Before asserting a provider identity or email, show the user the resource name, resource logo,
    and requested scopes from discovery and ask for consent. Anonymous registration does not need
    an identity consent prompt.

    ## 3. Register

    ### Anonymous

    ```http
    POST #{origin}/agent/identity
    Content-Type: application/json

    {"type":"anonymous"}
    ```

    The response contains `identity_assertion`, `assertion_expires`, `pre_claim_scopes`, `claim_token`,
    `claim_token_expires`, and `post_claim_scopes`. Keep the claim token in memory. Exchange the identity
    assertion immediately if you only need pre-claim access, or start the claim ceremony later.

    ```json
    {
      "registration_id":"reg_...",
      "registration_type":"anonymous",
      "identity_assertion":"<Tuist-signed assertion>",
      "assertion_expires":"<timestamp>",
      "pre_claim_scopes":["mcp"],
      "claim_url":"#{origin}/agent/identity/claim",
      "claim_token":"clm_...",
      "claim_token_expires":"<timestamp>",
      "post_claim_scopes":["mcp"]
    }
    ```

    ### Service-authenticated email

    Confirm the exact email with the user first, then send:

    ```http
    POST #{origin}/agent/identity
    Content-Type: application/json

    {"type":"service_auth","login_hint":"user@example.com"}
    ```

    This response has no identity assertion yet. It includes `claim_token` and a `claim` block with
    `verification_uri`, `user_code`, `expires_in`, and `interval`. Continue at the claim ceremony.

    ```json
    {
      "registration_id":"reg_...",
      "registration_type":"service_auth",
      "claim_url":"#{origin}/agent/identity/claim",
      "claim_token":"clm_...",
      "claim_token_expires":"<timestamp>",
      "post_claim_scopes":["mcp"],
      "claim":{
        "user_code":"123456",
        "expires_in":600,
        "verification_uri":"#{origin}/agent/identity/claim?claim_attempt_token=...",
        "interval":5
      }
    }
    ```

    ### Provider identity assertion

    The provider-signed assertion must use `typ: oauth-id-jag+jwt`, audience `#{origin}`, a fresh unique
    token identifier, a near-term expiry, a verified email, and `auth_time` showing authentication within
    the advertised maximum age.

    ```http
    POST #{origin}/agent/identity
    Content-Type: application/json

    {
      "type":"identity_assertion",
      "assertion_type":"urn:ietf:params:oauth:token-type:id-jag",
      "assertion":"<provider-signed assertion>"
    }
    ```

    A clean match returns Tuist's `identity_assertion`. If the provider identity matches an existing
    account that has not been linked before, Tuist returns `401 interaction_required` with a claim block.
    Surface that ceremony to the user. If Tuist returns `401 login_required`, re-authenticate the user at
    the provider and mint a fresh assertion. Signing in at Tuist cannot fix stale provider authentication.

    ```json
    {
      "registration_id":"reg_...",
      "registration_type":"identity_assertion",
      "identity_assertion":"<Tuist-signed assertion>",
      "assertion_expires":"<timestamp>",
      "scopes":["mcp"]
    }
    ```

    ## 4. Claim ceremony

    `service_auth` already returned the ceremony materials. For anonymous registration, first ask the
    user to confirm their exact Tuist email, then start an attempt:

    ```http
    POST #{origin}/agent/identity/claim
    Content-Type: application/json

    {"claim_token":"clm_...","email":"user@example.com"}
    ```

    ```json
    {
      "registration_id":"reg_...",
      "claim_attempt_id":"cla_...",
      "status":"initiated",
      "expires_at":"<timestamp>",
      "claim_attempt":{
        "user_code":"123456",
        "expires_in":600,
        "verification_uri":"#{origin}/agent/identity/claim?claim_attempt_token=...",
        "interval":5
      }
    }
    ```

    Surface `verification_uri` and `user_code` together. Tell the user to open the link, sign in or sign
    up with Tuist, and enter the six-digit code on the Tuist page. Do not ask the user to send the code
    back to you. The code travels from the agent to the user.

    Poll the token endpoint no faster than the returned `interval`:

    ```http
    POST #{origin}/oauth2/token
    Content-Type: application/x-www-form-urlencoded

    grant_type=urn:workos:agent-auth:grant-type:claim&claim_token=clm_...
    ```

    `authorization_pending` means the user has not finished. `slow_down` means increase the interval.
    `expired_token` means the six-digit code or outer claim window expired. For an anonymous registration,
    re-call the claim endpoint with the same claim token and email to mint a fresh attempt. For `service_auth`
    or a provider first-link ceremony, register again. If an anonymous restart returns `claim_expired`,
    register again.

    Success is a standard Open Authorization token response plus a new `identity_assertion` and
    `assertion_expires`. Drop any anonymous pre-claim access token; Tuist revokes it when the claim completes.

    ## 5. Exchange an identity assertion

    Use the [JSON Web Token bearer grant](https://www.rfc-editor.org/rfc/rfc7523.html):

    ```http
    POST #{origin}/oauth2/token
    Content-Type: application/x-www-form-urlencoded

    grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer
    &assertion=<Tuist-signed identity assertion>
    &resource=#{origin}/mcp
    ```

    The response contains `access_token`, `token_type: Bearer`, `expires_in`, and `scope`. Tuist does not
    issue a refresh token for this flow. Re-exchange the same identity assertion when the access token
    expires. If exchange returns `invalid_grant`, restart registration.

    ```json
    {
      "access_token":"<access token>",
      "token_type":"Bearer",
      "expires_in":3600,
      "scope":"mcp"
    }
    ```

    ## 6. Call Tuist

    ```http
    Authorization: Bearer <access_token>
    ```

    Use the bearer token at `#{origin}/mcp`. A claimed token runs with the signed-in user's normal Tuist
    permissions. An unclaimed anonymous token can discover capabilities but cannot perform actions that
    require a claimed user.

    ## Revocation

    Revoke one access token with the
    [Open Authorization token revocation endpoint](https://www.rfc-editor.org/rfc/rfc7009.html):

    ```http
    POST #{origin}/oauth2/revoke
    Content-Type: application/x-www-form-urlencoded

    token=<access_token>&token_type_hint=access_token
    ```

    The response is always `200 OK` for a well-formed request, including unknown or already-revoked tokens.
    The identity assertion remains usable.

    Trusted providers can revoke an entire linked registration by pushing a signed
    [Security Event Token](https://www.rfc-editor.org/rfc/rfc8417.html) to the advertised events endpoint
    with content type `application/secevent+jwt`. That invalidates the registration and every derived access
    token. Agents do not call the events endpoint.

    ## Errors

    | Error | Endpoint | Agent action |
    | --- | --- | --- |
    | `invalid_issuer`, `invalid_signature`, `expired`, `replay_detected`, `invalid_audience`, `invalid_client_id`, `missing_verified_email` | `/agent/identity` | Discard the provider assertion and correct or refresh it before retrying. |
    | `invalid_request` | `/agent/identity` | Correct the request shape. Do not resend it unchanged. |
    | `interaction_required` | `/agent/identity` | Surface the returned claim ceremony. |
    | `login_required` | `/agent/identity` | Re-authenticate at the provider and mint a fresh provider assertion. |
    | `invalid_claim_token` | `/agent/identity/claim` | Discard the claim token and register again. |
    | `claimed_or_in_flight` | `/agent/identity/claim` | Continue the ceremony already returned, or poll its claim token. |
    | `claim_expired` | `/agent/identity/claim` | Register again. |
    | `invalid_grant` | `/oauth2/token` | Discard the Tuist identity assertion and register again. |
    | `invalid_client`, `unsupported_grant_type` | `/oauth2/token` | Correct the token request or use one of the discovered grant types. |
    | `authorization_pending` | `/oauth2/token` | Wait for the advertised interval and poll again. |
    | `slow_down` | `/oauth2/token` | Add at least five seconds to the polling interval. |
    | `expired_token` | `/oauth2/token` | Restart an anonymous claim attempt, or register again for other flows. |
    | `sso_required` | Claim page | Single sign-on is required; the user must authenticate through their organization's provider. |
    | `rate_limited` | Registration or claim | Back off before retrying. |

    Retry server errors with exponential backoff. Do not retry a client error with the same unchanged payload.

    ## Compatibility

    Older Tuist clients may continue using `/agent/auth`, `/agent/auth/claim`, and `/agent/auth/revoke`.
    New agents must use the discovered current endpoints above because only those implement assertion exchange,
    browser-entered user codes, standard token revocation, and security-event delivery.

    ## Service information

    - Pricing: `https://tuist.dev/pricing`
    - Terms of service: `https://tuist.dev/terms`
    - Privacy policy: `https://tuist.dev/privacy`
    - Contact: `mailto:contact@tuist.dev`
    """
  end
end
