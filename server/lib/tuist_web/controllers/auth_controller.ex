defmodule TuistWeb.AuthController do
  @moduledoc """
  Auth controller.
  """

  use TuistWeb, :controller

  alias OAuth2.Client
  alias OAuth2.Strategy.AuthCode
  alias Tuist.Accounts
  alias Tuist.Accounts.Organization
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

          authorize_params =
            maybe_put_login_hint(
              [scope: "openid email profile", state: state],
              params["login_hint"]
            )

          url =
            config
            |> sso_client(sso_callback_url(route_provider))
            |> Client.authorize_url!(authorize_params)

          conn
          |> put_session(:sso_organization_id, organization_id)
          |> put_session(:sso_state, state)
          |> put_session(:sso_route_provider, route_provider)
          |> redirect(external: url)
        else
          _ ->
            raise UnauthorizedError,
                  dgettext("dashboard", "Failed to authenticate with the SSO provider.")
        end

      _ ->
        raise UnauthorizedError,
              dgettext("dashboard", "Failed to authenticate with the SSO provider.")
    end
  end

  defp sso_callback(conn, _params, _route_provider) do
    case {get_session(conn, :sso_organization_id), get_session(conn, :sso_state)} do
      {organization_id, state} when not is_nil(organization_id) and not is_nil(state) ->
        if conn.params["state"] != state do
          raise UnauthorizedError,
                dgettext("dashboard", "Failed to authenticate with the SSO provider.")
        end

        route_provider = get_session(conn, :sso_route_provider) || :oauth2

        with {:ok, %Organization{} = organization} <- Accounts.get_organization_by_id(organization_id),
             {:ok, config} <- Accounts.oauth2_config_for_organization(organization),
             {:ok, auth} <- sso_auth(conn, config, organization.sso_provider, route_provider) do
          conn
          |> delete_session(:sso_organization_id)
          |> delete_session(:sso_state)
          |> delete_session(:sso_route_provider)
          |> complete_oauth_callback(auth)
        else
          {:error, reason} ->
            log(:error, "Failed SSO callback: #{inspect(reason)}")

            raise UnauthorizedError,
                  dgettext("dashboard", "Failed to authenticate with the SSO provider.")

          _ ->
            raise UnauthorizedError,
                  dgettext("dashboard", "Failed to authenticate with the SSO provider.")
        end

      _ ->
        raise UnauthorizedError,
              dgettext("dashboard", "Failed to authenticate with the SSO provider.")
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

  defp complete_oauth_callback(conn, auth) do
    auth_params = %{auth_method: auth.provider}

    case Accounts.get_oauth2_identity(auth.provider, auth.uid) do
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
        provider_organization_id = Accounts.extract_provider_organization_id(auth)
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
        end
    end
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

            conn
            |> delete_session(:pending_oauth_signup)
            |> put_session(:user_return_to, oauth_return_url)
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
        dgettext("dashboard", "Failed to authenticate.")
    end
  end

  defp sso_client(config, redirect_uri) do
    [
      strategy: AuthCode,
      client_id: config.client_id,
      client_secret: config.client_secret,
      site: config.site,
      authorize_url: config.authorize_url,
      token_url: config.token_url,
      redirect_uri: redirect_uri
    ]
    |> Client.new()
    |> Client.put_serializer("application/json", JSON)
  end

  defp sso_auth(conn, config, sso_provider, route_provider) do
    params = [code: conn.params["code"]]

    with {:ok, %Client{token: token} = client} <-
           Client.get_token(sso_client(config, sso_callback_url(route_provider)), params),
         {:ok, %{status_code: 200, body: userinfo}} <- Client.get(client, config.user_info_url),
         {:ok, uid, email} <- validate_sso_userinfo(userinfo) do
      {:ok, build_sso_auth(token, userinfo, uid, email, sso_provider, config.provider_organization_id)}
    else
      {:ok, %{status_code: status_code, body: body}} -> {:error, {:userinfo_request_failed, status_code, body}}
      {:error, reason} -> {:error, reason}
      error -> {:error, error}
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
      strategy: AuthCode,
      uid: uid,
      info: %Info{
        name: name,
        first_name: userinfo["given_name"],
        last_name: userinfo["family_name"],
        nickname: userinfo["preferred_username"],
        email: email
      },
      credentials: %Credentials{
        token: token.access_token,
        refresh_token: token.refresh_token,
        expires_at: token.expires_at,
        token_type: token.token_type,
        expires: !!token.expires_at,
        scopes: token.other_params["scope"]
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

  defp sso_callback_url(:okta), do: TuistWeb.Endpoint.url() <> ~p"/users/auth/okta/callback"
  defp sso_callback_url(:oauth2), do: TuistWeb.Endpoint.url() <> ~p"/users/auth/custom_oauth2/callback"

  defp maybe_put_login_hint(params, login_hint) when is_binary(login_hint) and login_hint != "" do
    Keyword.put(params, :login_hint, login_hint)
  end

  defp maybe_put_login_hint(params, _login_hint), do: params
end
