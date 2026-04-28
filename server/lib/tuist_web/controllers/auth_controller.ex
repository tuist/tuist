defmodule TuistWeb.AuthController do
  @moduledoc """
  Auth controller.
  """

  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Accounts.Organization
  alias Tuist.OAuth2.SSOClient
  alias TuistWeb.Authentication
  alias TuistWeb.Errors.UnauthorizedError
  alias Ueberauth.Auth
  alias Ueberauth.Auth.Credentials
  alias Ueberauth.Auth.Extra
  alias Ueberauth.Auth.Info
  alias Ueberauth.Failure.Error

  require Logger

  defp log(level, message) do
    if not Tuist.Environment.test?() do
      Logger.log(level, "[OAuth2] #{message}")
    end
  end

  def request(_conn, _params) do
    raise TuistWeb.Errors.NotFoundError,
          dgettext("dashboard", "The authentication URL is not supported")
  end

  def okta_request(conn, params), do: sso_request(conn, params, :okta)
  def oauth2_request(conn, params), do: sso_request(conn, params, :oauth2)

  def okta_callback(conn, params), do: sso_callback(conn, params, :okta)
  def oauth2_callback(conn, params), do: sso_callback(conn, params, :oauth2)

  defp sso_request(conn, params, route_provider) do
    case params do
      %{"organization_id" => organization_id} ->
        with {:ok, %Organization{} = organization} <- Accounts.get_organization_by_id(organization_id),
             {:ok, config} <- Accounts.oauth2_config_for_organization(organization) do
          state = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

          query_params =
            maybe_put_login_hint(
              %{
                response_type: "code",
                client_id: config.client_id,
                redirect_uri: sso_callback_url(route_provider),
                scope: "openid email profile",
                state: state
              },
              params["login_hint"]
            )

          url = config.authorize_url <> "?" <> URI.encode_query(query_params)

          conn
          |> put_session(:sso_organization_id, organization_id)
          |> put_session(:sso_state, state)
          |> put_session(:sso_route_provider, route_provider)
          |> redirect(external: url)
        else
          {:error, :not_found} ->
            raise_sso_unauthorized(:organization_not_found)

          {:error, :oauth2_not_configured} ->
            raise_sso_unauthorized(:sso_not_configured)

          _ ->
            raise_sso_unauthorized(:sso_request_failed)
        end

      _ ->
        raise_sso_unauthorized(:missing_organization_id)
    end
  end

  defp sso_callback(conn, _params, _route_provider) do
    case {get_session(conn, :sso_organization_id), get_session(conn, :sso_state)} do
      {organization_id, state} when not is_nil(organization_id) and not is_nil(state) ->
        if conn.params["state"] != state do
          raise_sso_unauthorized(:state_mismatch)
        end

        validate_sso_callback_params!(conn.params)

        route_provider = get_session(conn, :sso_route_provider) || :oauth2

        with {:ok, %Organization{} = organization} <- Accounts.get_organization_by_id(organization_id),
             {:ok, config} <- Accounts.oauth2_config_for_organization(organization),
             {:ok, auth} <- sso_auth(conn, config, organization.sso_provider, route_provider) do
          conn
          |> delete_session(:sso_organization_id)
          |> delete_session(:sso_state)
          |> delete_session(:sso_route_provider)
          |> complete_oauth_callback(auth, sso_organization: organization)
        else
          {:error, :not_found} ->
            raise_sso_unauthorized(:organization_not_found)

          {:error, :oauth2_not_configured} ->
            raise_sso_unauthorized(:sso_not_configured)

          {:error, reason} ->
            log(:error, "Failed SSO callback: #{inspect(reason)}")
            raise_sso_unauthorized(reason)

          _ ->
            raise_sso_unauthorized(:sso_callback_failed)
        end

      _ ->
        raise_sso_unauthorized(:expired_session)
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "You have been logged out!")
    |> clear_session()
    |> redirect(to: ~p"/")
    |> halt()
  end

  def callback(%{assigns: %{ueberauth_failure: failure}} = _conn, _params) do
    log(
      :error,
      "Ueberauth failed authenticating: #{inspect(failure)}"
    )

    raise UnauthorizedError, oauth_failure_message(failure)
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    complete_oauth_callback(conn, auth)
  end

  defp complete_oauth_callback(conn, auth, opts \\ []) do
    auth_params = %{auth_method: auth.provider}
    sso_organization = Keyword.get(opts, :sso_organization)
    provider_organization_id = Accounts.extract_provider_organization_id(auth)

    case Accounts.get_oauth2_identity(auth.provider, auth.uid, provider_organization_id) do
      {:ok, oauth2_identity} ->
        user = oauth2_identity.user
        oauth_return_url = get_session(conn, :oauth_return_to)

        if oauth_return_url do
          conn
          |> put_session(:user_return_to, oauth_return_url)
          |> delete_session(:oauth_return_to)
          |> Authentication.log_in_user(user, auth_params)
        else
          Authentication.log_in_user(conn, user, auth_params)
        end

      {:error, :not_found} ->
        oauth_return_url = get_session(conn, :oauth_return_to)

        case Accounts.get_user_by_email(auth.info.email) do
          {:error, :not_found} ->
            oauth_data = %{
              "provider" => to_string(auth.provider),
              "uid" => to_string(auth.uid),
              "email" => auth.info.email,
              "provider_organization_id" => provider_organization_id,
              "oauth_return_url" => oauth_return_url
            }

            conn
            |> delete_session(:oauth_return_to)
            |> put_session(:pending_oauth_signup, oauth_data)
            |> redirect(to: ~p"/users/choose-username")
            |> halt()

          {:ok, existing_user} ->
            link_existing_user_and_log_in(
              conn,
              existing_user,
              auth,
              auth_params,
              sso_organization,
              provider_organization_id,
              oauth_return_url
            )
        end
    end
  end

  defp link_existing_user_and_log_in(
         conn,
         existing_user,
         auth,
         auth_params,
         sso_organization,
         provider_organization_id,
         oauth_return_url
       ) do
    cond do
      can_link_existing_user?(existing_user, auth.provider, sso_organization) ->
        {:ok, _oauth_identity} =
          Accounts.link_oauth_identity_to_user(existing_user, %{
            provider: auth.provider,
            id_in_provider: to_string(auth.uid),
            provider_organization_id: provider_organization_id
          })

        if oauth_return_url do
          conn
          |> put_session(:user_return_to, oauth_return_url)
          |> delete_session(:oauth_return_to)
          |> Authentication.log_in_user(existing_user, auth_params)
        else
          Authentication.log_in_user(conn, existing_user, auth_params)
        end

      invitation = pending_invitation_for(existing_user, sso_organization) ->
        # The user came in through SSO but isn't a member of the org yet —
        # however, an admin has issued them an invitation. Send them to the
        # accept page so they can review and explicitly accept; we don't
        # want to silently flip membership during a login redirect.
        conn
        |> redirect(to: ~p"/auth/invitations/#{invitation.token}")
        |> halt()

      true ->
        log(
          :warning,
          "Refused to link existing user #{existing_user.id} via custom SSO provider #{auth.provider}: user is not a member of the authenticating organization."
        )

        raise_sso_unauthorized(:existing_user_not_member)
    end
  end

  # Custom SSO providers (Okta, generic OAuth2) let an admin configure
  # arbitrary authorize/token/userinfo endpoints. A malicious admin could
  # return any email from /userinfo and take over an existing Tuist account
  # via email-based auto-linking. We only auto-link when the existing user
  # is already a member of the authenticating organization, since the admin
  # already has access to manage that user.
  defp can_link_existing_user?(_user, provider, _organization) when provider not in [:okta, :oauth2], do: true
  defp can_link_existing_user?(_user, _provider, nil), do: false

  defp can_link_existing_user?(user, _provider, %Organization{} = organization) do
    Accounts.belongs_to_organization?(user, organization)
  end

  defp pending_invitation_for(_user, nil), do: nil

  defp pending_invitation_for(%{email: email}, %Organization{} = organization) do
    Accounts.get_invitation_by_invitee_email_and_organization(email, organization)
  end

  def authenticate_cli_deprecated(conn, params) do
    conn
    |> redirect(to: ~p"/auth/device_codes/#{params["device_code"]}?type=cli")
    |> halt()
  end

  def authenticate_device_code(conn, params) do
    device_code = params["device_code"]
    create_device_code_if_absent(device_code)

    type = params["type"] || "cli"

    conn
    |> redirect(to: ~p"/auth/device_codes/#{device_code}/success?type=#{type}")
    |> halt()
  end

  defp create_device_code_if_absent(device_code) do
    if is_nil(Accounts.get_device_code(device_code)) do
      Accounts.create_device_code(device_code)
    end
  end

  def complete_signup(conn, %{"token" => token}) do
    case Phoenix.Token.verify(TuistWeb.Endpoint, "signup_completion", token, max_age: 300) do
      {:ok, %{user_id: user_id, oauth_return_url: oauth_return_url}} ->
        case Accounts.get_user_by_id(user_id) do
          nil ->
            redirect(conn, to: ~p"/users/log_in")

          user ->
            pending = get_session(conn, :pending_oauth_signup)
            auth_method = if pending, do: String.to_existing_atom(pending["provider"]), else: :password

            return_to =
              oauth_return_url ||
                if user |> Accounts.get_user_organization_accounts() |> Enum.empty?(), do: ~p"/organizations/new"

            conn
            |> delete_session(:pending_oauth_signup)
            |> put_session(:user_return_to, return_to)
            |> Authentication.log_in_user(user, %{auth_method: auth_method})
        end

      {:error, _reason} ->
        redirect(conn, to: ~p"/users/log_in")
    end
  end

  def complete_signup(conn, _params) do
    redirect(conn, to: ~p"/users/log_in")
  end

  defp oauth_failure_message(%Ueberauth.Failure{errors: errors}) do
    case errors do
      [%Error{message_key: "access_denied"} | _] ->
        dgettext(
          "dashboard",
          "Your identity provider denied access. Please ask your organization admin to assign you to the Tuist application."
        )

      [%Error{message: message} | _] when is_binary(message) and message != "" ->
        message

      _ ->
        dgettext(
          "dashboard",
          "Authentication with the identity provider failed. Please try again."
        )
    end
  end

  defp sso_auth(conn, config, sso_provider, route_provider) do
    with :ok <- validate_sso_urls(config),
         {:ok, token_body} <-
           SSOClient.exchange_token(
             config.token_url,
             conn.params["code"],
             sso_callback_url(route_provider),
             config.client_id,
             config.client_secret
           ),
         {:ok, userinfo} <- SSOClient.fetch_userinfo(config.user_info_url, token_body["access_token"]),
         {:ok, uid, email} <- validate_sso_userinfo(userinfo) do
      {:ok, build_sso_auth(token_body, userinfo, uid, email, sso_provider, config.provider_organization_id)}
    else
      {:error, reason} -> {:error, reason}
      error -> {:error, error}
    end
  end

  # The IdP can redirect back to our callback without a `code` (RFC 6749 §4.1.2.1):
  # the user can deny consent, the IdP can refuse the request, the request can
  # expire, etc. In all those cases the IdP sends `?error=...&error_description=...`
  # and we must surface a clean 401 instead of trying to exchange a missing code.
  defp validate_sso_callback_params!(%{"error" => error} = params) when is_binary(error) and error != "" do
    description = params["error_description"]

    log(
      :warning,
      "SSO provider returned error during callback: #{error}" <>
        if(is_binary(description) and description != "", do: " — #{description}", else: "")
    )

    raise_sso_unauthorized({:provider_returned_error, error})
  end

  defp validate_sso_callback_params!(%{"code" => code}) when is_binary(code) and code != "" do
    :ok
  end

  defp validate_sso_callback_params!(_params) do
    log(:warning, "SSO callback request is missing both `code` and `error` parameters")
    raise_sso_unauthorized(:missing_authorization_code)
  end

  defp validate_sso_urls(config) do
    urls =
      Enum.filter(
        [config.site, config.authorize_url, config.token_url, config.user_info_url],
        &String.starts_with?(&1, "http")
      )

    if Enum.all?(urls, &Tuist.URL.public_url?/1) do
      :ok
    else
      {:error, :unsafe_sso_url}
    end
  end

  defp validate_sso_userinfo(userinfo) do
    uid = userinfo["sub"] || userinfo["id"] || userinfo["email"]
    email = userinfo["email"]

    cond do
      is_nil(uid) or uid == "" ->
        {:error, :missing_user_identifier}

      is_nil(email) or email == "" ->
        {:error, :missing_email}

      true ->
        {:ok, uid, email}
    end
  end

  defp build_sso_auth(token, userinfo, uid, email, sso_provider, provider_organization_id) do
    name = userinfo["name"] || userinfo["preferred_username"] || userinfo["email"] || userinfo["sub"]

    %Auth{
      provider: sso_provider,
      strategy: Ueberauth.Strategy.OAuth2,
      uid: uid,
      info: %Info{
        name: name,
        first_name: userinfo["given_name"],
        last_name: userinfo["family_name"],
        nickname: userinfo["preferred_username"],
        email: email
      },
      credentials: %Credentials{
        token: token["access_token"],
        refresh_token: token["refresh_token"],
        expires_at: compute_expires_at(token["expires_in"]),
        token_type: token["token_type"],
        expires: not is_nil(token["expires_in"]),
        scopes: String.split(token["scope"] || "", " ", trim: true)
      },
      extra: %Extra{
        raw_info: %{
          token: token,
          user: userinfo,
          provider_organization_id: provider_organization_id
        }
      }
    }
  end

  defp compute_expires_at(nil), do: nil
  defp compute_expires_at(expires_in) when is_integer(expires_in), do: System.system_time(:second) + expires_in

  defp compute_expires_at(expires_in) when is_binary(expires_in) do
    case Integer.parse(expires_in) do
      {seconds, _} -> System.system_time(:second) + seconds
      :error -> nil
    end
  end

  defp raise_sso_unauthorized(reason) do
    raise UnauthorizedError, sso_unauthorized_message(reason)
  end

  defp sso_unauthorized_message(:missing_organization_id) do
    dgettext(
      "dashboard",
      "The SSO request is missing an organization identifier. Please start the sign-in flow again from the login page."
    )
  end

  defp sso_unauthorized_message(:organization_not_found) do
    dgettext(
      "dashboard",
      "We couldn't find the organization for this SSO request. Please verify that you are using the correct SSO link."
    )
  end

  defp sso_unauthorized_message(:sso_not_configured) do
    dgettext(
      "dashboard",
      "SSO is not fully configured for this organization. Ask an organization admin to review the SSO settings."
    )
  end

  defp sso_unauthorized_message(:expired_session) do
    dgettext(
      "dashboard",
      "Your SSO session has expired. Please restart the sign-in flow from the login page."
    )
  end

  defp sso_unauthorized_message(:state_mismatch) do
    dgettext(
      "dashboard",
      "The SSO response could not be validated because the request state did not match. Please try again."
    )
  end

  defp sso_unauthorized_message({:provider_returned_error, "access_denied"}) do
    dgettext(
      "dashboard",
      "Your identity provider denied access. Please ask your organization admin to assign you to the Tuist application."
    )
  end

  defp sso_unauthorized_message({:provider_returned_error, _error}) do
    dgettext(
      "dashboard",
      "Your identity provider returned an authentication error. Please try again or contact your organization admin."
    )
  end

  defp sso_unauthorized_message(:missing_authorization_code) do
    dgettext(
      "dashboard",
      "The SSO provider callback is missing an authorization code. Please restart the sign-in flow."
    )
  end

  defp sso_unauthorized_message(:unsafe_sso_url) do
    dgettext(
      "dashboard",
      "The configured SSO endpoints are invalid. Ask your organization admin to review the SSO settings."
    )
  end

  defp sso_unauthorized_message({:token_exchange_failed, _status, _body}) do
    dgettext(
      "dashboard",
      "Tuist couldn't exchange the authorization code with your identity provider. Ask your organization admin to verify the SSO credentials and callback URL."
    )
  end

  defp sso_unauthorized_message({:userinfo_request_failed, _status, _body}) do
    dgettext(
      "dashboard",
      "Tuist couldn't fetch your profile from your identity provider. Ask your organization admin to verify the user info endpoint and configured scopes."
    )
  end

  defp sso_unauthorized_message(:invalid_grant) do
    dgettext(
      "dashboard",
      "The SSO authorization code is invalid or expired. Please restart the sign-in flow."
    )
  end

  defp sso_unauthorized_message(:missing_user_identifier) do
    dgettext(
      "dashboard",
      "Your identity provider response is missing a stable user identifier. Ask your organization admin to review the user info claims."
    )
  end

  defp sso_unauthorized_message(:missing_email) do
    dgettext(
      "dashboard",
      "Your identity provider response is missing an email address. Ask your organization admin to include the email claim."
    )
  end

  defp sso_unauthorized_message(:existing_user_not_member) do
    dgettext(
      "dashboard",
      "Your Tuist account already exists, but it isn't a member of this organization. Ask an organization admin to add you, then sign in with SSO again."
    )
  end

  defp sso_unauthorized_message(:sso_request_failed) do
    dgettext(
      "dashboard",
      "We couldn't start the SSO flow for this organization. Please verify the SSO configuration and try again."
    )
  end

  defp sso_unauthorized_message(:sso_callback_failed) do
    dgettext(
      "dashboard",
      "We couldn't complete the SSO callback for this request. Please try again."
    )
  end

  defp sso_unauthorized_message(_reason) do
    dgettext(
      "dashboard",
      "Failed to authenticate with the SSO provider. Please try again."
    )
  end

  defp sso_callback_url(:okta), do: TuistWeb.Endpoint.url() <> ~p"/users/auth/okta/callback"
  defp sso_callback_url(:oauth2), do: TuistWeb.Endpoint.url() <> ~p"/users/auth/oauth2/callback"

  defp maybe_put_login_hint(params, login_hint) when is_binary(login_hint) and login_hint != "" do
    Map.put(params, :login_hint, login_hint)
  end

  defp maybe_put_login_hint(params, _login_hint), do: params
end
