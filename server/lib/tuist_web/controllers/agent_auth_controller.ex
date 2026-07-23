defmodule TuistWeb.AgentAuthController do
  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Environment
  alias TuistWeb.AgentAuthDocument
  alias TuistWeb.RateLimit.AgentAuth
  alias TuistWeb.RemoteIp

  @supported_assertion_type "verified_email"
  @id_jag_assertion_type "urn:ietf:params:oauth:token-type:id-jag"
  @supported_assertion_types ["verified_email", "urn:ietf:params:oauth:token-type:id-jag"]
  @supported_credential_types ["access_token", "api_key"]

  def auth_md(conn, _params) do
    conn
    |> put_resp_content_type("text/markdown")
    |> send_resp(:ok, AgentAuthDocument.render(canonical_origin()))
  end

  def identity(conn, %{"type" => "anonymous"}) do
    with {:allow, _count} <- AgentAuth.hit_registration(conn, :anonymous),
         {:ok, result} <-
           Accounts.create_protocol_agent_registration(%{
             registration_type: :anonymous,
             audience: canonical_origin(),
             registration_ip: RemoteIp.get(conn)
           }) do
      json(conn, %{
        registration_id: external_registration_id(result.registration),
        registration_type: "anonymous",
        identity_assertion: result.identity_assertion,
        assertion_expires: result.assertion_expires_at,
        pre_claim_scopes: result.pre_claim_scopes,
        claim_url: protocol_claim_url(),
        claim_token: result.claim_token,
        claim_token_expires: result.claim_token_expires_at,
        post_claim_scopes: result.post_claim_scopes
      })
    else
      {:deny, _limit} ->
        render_identity_error(conn, :too_many_requests, "rate_limited", "Too many anonymous registrations.")

      {:error, _reason} ->
        render_identity_error(conn, :bad_request, "invalid_request", "The anonymous registration failed.")
    end
  end

  def identity(conn, %{"type" => "service_auth", "login_hint" => login_hint}) do
    with {:allow, _count} <- AgentAuth.hit_registration(conn, :service_auth),
         {:ok, result} <-
           Accounts.create_protocol_agent_registration(%{
             registration_type: :service_auth,
             login_hint: login_hint,
             audience: canonical_origin(),
             registration_ip: RemoteIp.get(conn)
           }) do
      json(conn, %{
        registration_id: external_registration_id(result.registration),
        registration_type: "service_auth",
        claim_url: protocol_claim_url(),
        claim_token: result.claim_token,
        claim_token_expires: result.claim_token_expires_at,
        post_claim_scopes: result.post_claim_scopes,
        claim:
          ceremony_block(
            result.claim_view_token,
            result.user_code,
            result.user_code_expires_at
          )
      })
    else
      {:deny, _limit} ->
        render_identity_error(conn, :too_many_requests, "rate_limited", "Too many service-auth registrations.")

      {:error, :invalid_email} ->
        render_identity_error(
          conn,
          :bad_request,
          "invalid_login_hint",
          "login_hint must be a valid email address."
        )

      {:error, _reason} ->
        render_identity_error(conn, :bad_request, "invalid_request", "The service-auth registration failed.")
    end
  end

  def identity(conn, %{
        "type" => "identity_assertion",
        "assertion_type" => @id_jag_assertion_type,
        "assertion" => assertion
      }) do
    with {:allow, _count} <- AgentAuth.hit_registration(conn, :identity_assertion),
         {:ok, result} <-
           Accounts.create_protocol_agent_registration(%{
             registration_type: :agent_provider,
             assertion: assertion,
             audience: canonical_origin(),
             registration_ip: RemoteIp.get(conn)
           }) do
      json(conn, %{
        registration_id: external_registration_id(result.registration),
        registration_type: "identity_assertion",
        identity_assertion: result.identity_assertion,
        assertion_expires: result.assertion_expires_at,
        scopes: result.scopes
      })
    else
      {:interaction_required, result} ->
        conn
        |> put_resp_header(
          "www-authenticate",
          ~s(AgentAuth error="interaction_required", error_description="User confirmation is required before linking this provider identity.")
        )
        |> put_status(:unauthorized)
        |> json(%{
          error: "interaction_required",
          error_description: "The provider identity matches an existing Tuist account and requires user confirmation.",
          registration_id: external_registration_id(result.registration),
          registration_type: "identity_assertion",
          claim_url: protocol_claim_url(),
          claim_token: result.claim_token,
          claim_token_expires: result.claim_token_expires_at,
          post_claim_scopes: result.post_claim_scopes,
          claim:
            ceremony_block(
              result.claim_view_token,
              result.user_code,
              result.user_code_expires_at
            )
        })

      {:deny, _limit} ->
        render_identity_error(conn, :too_many_requests, "rate_limited", "Too many identity registrations.")

      {:error, reason} when reason in [:auth_time_missing, :auth_time_too_old] ->
        render_login_required(conn, reason)

      {:error, reason}
      when reason in [
             :invalid_issuer,
             :invalid_signature,
             :invalid_key,
             :expired,
             :replay_detected,
             :invalid_audience,
             :invalid_client_id,
             :missing_verified_email,
             :insufficient_user_authentication
           ] ->
        render_identity_error(
          conn,
          :bad_request,
          if(reason == :invalid_key, do: "invalid_signature", else: Atom.to_string(reason)),
          "The provider identity assertion is invalid."
        )

      {:error, _reason} ->
        render_identity_error(
          conn,
          :internal_server_error,
          "server_error",
          "The identity registration could not be completed."
        )
    end
  end

  def identity(conn, %{"type" => "identity_assertion"}) do
    render_identity_error(
      conn,
      :bad_request,
      "invalid_request",
      "Only the Identity Assertion Authorization Grant assertion type is supported."
    )
  end

  def identity(conn, _params) do
    render_identity_error(conn, :bad_request, "invalid_request", "The identity registration request is invalid.")
  end

  def protocol_claim(conn, %{"claim_token" => claim_token, "email" => email}) do
    with {:allow, _count} <- AgentAuth.hit(conn, email),
         {:ok, result} <-
           Accounts.initiate_protocol_agent_claim(%{
             claim_token: claim_token,
             email: email,
             claim_requested_ip: RemoteIp.get(conn)
           }) do
      json(conn, %{
        registration_id: external_registration_id(result.registration),
        claim_attempt_id: result.registration.claim_attempt_id,
        status: "initiated",
        expires_at: result.user_code_expires_at,
        claim_attempt:
          ceremony_block(
            result.claim_view_token,
            result.user_code,
            result.user_code_expires_at
          )
      })
    else
      {:deny, _limit} ->
        render_protocol_error(conn, :too_many_requests, "rate_limited", "Too many claim attempts.")

      {:error, :invalid_email} ->
        render_protocol_error(conn, :bad_request, "invalid_request", "email must be a valid email address.")

      {:error, :invalid_claim_token} ->
        render_protocol_error(conn, :unauthorized, "invalid_claim_token", "The claim token is invalid.")

      {:error, :claim_expired} ->
        render_protocol_error(conn, :gone, "claim_expired", "The registration has expired.")

      {:error, :previously_claimed} ->
        render_protocol_error(conn, :conflict, "claimed_or_in_flight", "The registration is already claimed.")

      {:error, :claim_not_available} ->
        render_protocol_error(
          conn,
          :conflict,
          "claimed_or_in_flight",
          "This registration already has claim ceremony materials."
        )
    end
  end

  def protocol_claim(conn, _params) do
    render_protocol_error(conn, :bad_request, "invalid_request", "claim_token and email are required.")
  end

  def protocol_claim_page(conn, %{"claim_attempt_token" => claim_attempt_token}) do
    case Accounts.protocol_agent_claim_view(claim_attempt_token, conn.assigns.current_user) do
      {:ok, result} ->
        conn
        |> put_status(:ok)
        |> render_agent_auth(
          :claim,
          claim_attempt_token: claim_attempt_token,
          email: conn.assigns.current_user.email,
          provider_name: result.provider_name,
          head_title: "Authorize agent · Tuist"
        )

      {:error, :wrong_account} ->
        render_claim_status(
          conn,
          :forbidden,
          "Wrong account",
          "Sign in with the email address the agent named."
        )

      {:error, :otp_expired} ->
        render_claim_status(conn, :gone, "Code expired", "Ask the agent to start a new claim attempt.")

      {:error, :previously_claimed} ->
        render_claim_status(
          conn,
          :ok,
          "Already authorized",
          "Return to the agent. It is already connected to Tuist."
        )

      {:error, _reason} ->
        render_claim_status(conn, :not_found, "Invalid link", "Ask the agent to start a new claim attempt.")
    end
  end

  def protocol_claim_page(conn, _params) do
    render_claim_status(conn, :bad_request, "Missing token", "This claim link is incomplete.")
  end

  def confirm_protocol_claim(conn, %{"claim_attempt_token" => claim_attempt_token, "user_code" => user_code}) do
    case Accounts.confirm_protocol_agent_claim(%{
           claim_view_token: claim_attempt_token,
           user_code: user_code,
           user: conn.assigns.current_user,
           auth_method: get_session(conn, :auth_method),
           claim_completed_ip: RemoteIp.get(conn)
         }) do
      {:ok, _result} ->
        render_claim_status(
          conn,
          :ok,
          "Agent authorized",
          "Return to the agent. It can now finish connecting to Tuist."
        )

      {:error, :wrong_account} ->
        render_claim_status(
          conn,
          :forbidden,
          "Wrong account",
          "Sign in with the email address the agent named."
        )

      {:error, :sso_required} ->
        render_claim_status(
          conn,
          :forbidden,
          "Single sign-on required",
          "Sign out and authenticate with your organization's identity provider."
        )

      {:error, reason} when reason in [:user_code_invalid, :rate_limited] ->
        render_claim_status(
          conn,
          :unauthorized,
          "Invalid code",
          "Check the six-digit code shown by the agent and try again."
        )

      {:error, _reason} ->
        render_claim_status(conn, :gone, "Claim expired", "Ask the agent to start a new claim attempt.")
    end
  end

  def confirm_protocol_claim(conn, _params) do
    render_claim_status(conn, :bad_request, "Invalid request", "A six-digit user code is required.")
  end

  def protocol_event(conn, _params) do
    with {:allow, _count} <- AgentAuth.hit(conn),
         {:ok, token, _conn} <- Plug.Conn.read_body(conn),
         :ok <- Accounts.receive_protocol_agent_event(String.trim(token), canonical_origin()) do
      send_resp(conn, :accepted, "")
    else
      {:deny, _limit} ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{err: "invalid_request", description: "Too many event deliveries."})

      {:error, reason} ->
        {error, description} = protocol_event_error(reason)

        conn
        |> put_status(:bad_request)
        |> json(%{err: error, description: description})

      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{err: "invalid_request", description: "A signed Security Event Token is required."})
    end
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
        |> put_status(:ok)
        |> render_agent_auth(
          :code,
          otp: otp,
          expires_at: Calendar.strftime(otp_expires_at, "%Y-%m-%d %H:%M UTC"),
          head_title: "Tuist sign-in code"
        )

      {:error, :otp_expired} ->
        render_claim_status(conn, :gone, "Code expired", "Ask the agent to start the claim again.")

      {:error, :claim_expired} ->
        render_claim_status(conn, :gone, "Registration expired", "Ask the agent to register again.")

      {:error, :previously_claimed} ->
        render_claim_status(
          conn,
          :conflict,
          "Already claimed",
          "This registration has already been completed."
        )

      {:error, :invalid_claim_token} ->
        render_claim_status(conn, :not_found, "Invalid link", "This claim link is no longer valid.")
    end
  end

  def claim_view(conn, _params) do
    render_claim_status(conn, :bad_request, "Missing token", "This claim link is incomplete.")
  end

  defp protocol_claim_url, do: "#{canonical_origin()}/agent/identity/claim"

  defp ceremony_block(claim_attempt_token, user_code, expires_at) do
    %{
      user_code: user_code,
      expires_in: max(DateTime.diff(expires_at, DateTime.utc_now(), :second), 0),
      verification_uri: "#{protocol_claim_url()}?claim_attempt_token=#{URI.encode_www_form(claim_attempt_token)}",
      interval: Accounts.agent_auth_poll_interval_seconds()
    }
  end

  defp render_protocol_error(conn, status, error, description) do
    conn
    |> put_status(status)
    |> json(%{error: error, error_description: description})
  end

  defp render_identity_error(conn, status, error, message) do
    conn
    |> put_status(status)
    |> json(%{error: error, message: message})
  end

  defp render_login_required(conn, reason) do
    max_age = Accounts.agent_auth_id_jag_max_auth_age_seconds()

    description =
      case reason do
        :auth_time_missing ->
          "The Identity Assertion Authorization Grant must include auth_time. Re-authenticate with the provider."

        :auth_time_too_old ->
          "The provider authentication is not recent enough. Re-authenticate with the provider."
      end

    conn
    |> put_resp_header(
      "www-authenticate",
      ~s(AgentAuth error="login_required", max_age="#{max_age}", error_description="#{description}")
    )
    |> put_status(:unauthorized)
    |> json(%{error: "login_required", error_description: description, max_age: max_age})
  end

  defp protocol_event_error(:invalid_issuer), do: {"invalid_issuer", "The Security Event Token issuer is not trusted."}

  defp protocol_event_error(:invalid_audience),
    do: {"invalid_audience", "The Security Event Token audience does not match Tuist."}

  defp protocol_event_error(reason) when reason in [:invalid_signature, :expired],
    do: {"authentication_failed", "The Security Event Token signature or lifetime is invalid."}

  defp protocol_event_error(:invalid_key),
    do: {"invalid_key", "The Security Event Token signing key is missing or unknown."}

  defp protocol_event_error(_reason),
    do: {"invalid_request", "The Security Event Token is malformed or has already been used."}

  defp external_registration_id(registration), do: "reg_#{registration.id}"

  # All outbound origins (audience binding for ID-JAG/logout tokens, emailed
  # claim links, and JSON `claim_url`s) come from the configured canonical
  # app URL, never from request headers — otherwise a caller could spoof
  # `X-Forwarded-Host` and have Tuist email a secret claim-view link to
  # an attacker-controlled origin.
  defp canonical_origin, do: Environment.app_url(route_type: :app)

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

  defp render_claim_status(conn, status, title, message) do
    conn
    |> put_status(status)
    |> render_agent_auth(
      :status,
      title: title,
      message: message,
      head_title: "#{title} · Tuist"
    )
  end

  defp render_agent_auth(conn, template, assigns) do
    conn
    |> put_view(TuistWeb.AgentAuthHTML)
    |> render(template, assigns)
  end
end
