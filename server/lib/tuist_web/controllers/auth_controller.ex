defmodule TuistWeb.AuthController do
  @moduledoc """
  Auth controller.
  """

  use TuistWeb, :controller

  alias OAuth2.Client
  alias OAuth2.Strategy.AuthCode
  alias Tuist.Accounts
  alias Tuist.Accounts.Organization
  alias Tuist.OAuth.CustomOAuth2
  alias Tuist.OAuth.Okta
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

  def okta_request(conn, params) do
    log(:info, "Starting Okta request with params: #{inspect(params)}")

    case params do
      %{"organization_id" => organization_id} ->
        log(:info, "Successfully extracted organization_id: #{organization_id}")

        case Accounts.get_organization_by_id(organization_id) do
          {:ok, %Organization{} = organization} ->
            log(:info, "Successfully found organization: #{inspect(organization.id)}")

            case Okta.config_for_organization(organization) do
              {:ok, config} ->
                log(
                  :info,
                  "Successfully retrieved Okta config for organization: #{organization.id}, domain: #{config.domain}"
                )

                strategy_options = okta_strategy_options(config, params)

                conn
                |> put_session(:okta_organization_id, organization_id)
                |> Ueberauth.run_request(
                  "okta",
                  {
                    Ueberauth.Strategy.Okta,
                    strategy_options
                  }
                )

              error ->
                log(
                  :error,
                  "Failed to get Okta config for organization #{organization.id}: #{inspect(error)}"
                )

                raise UnauthorizedError,
                      dgettext("dashboard", "Failed to authenticate with Okta.")
            end

          error ->
            log(
              :error,
              "Failed to find organization with id #{organization_id}: #{inspect(error)}"
            )

            raise UnauthorizedError,
                  dgettext("dashboard", "Failed to authenticate with Okta.")
        end

      error ->
        log(
          :error,
          "Failed to extract organization_id from params: #{inspect(params)}, error: #{inspect(error)}"
        )

        raise UnauthorizedError,
              dgettext("dashboard", "Failed to authenticate with Okta.")
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

  def custom_oauth2_request(conn, params) do
    case params do
      %{"organization_id" => organization_id} ->
        with {:ok, %Organization{} = organization} <- Accounts.get_organization_by_id(organization_id),
             {:ok, config} <- CustomOAuth2.config_for_organization(organization) do
          state = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

          authorize_params =
            maybe_put_login_hint(
              [scope: "openid email profile", state: state],
              params["login_hint"]
            )

          url =
            config
            |> custom_oauth2_client(custom_oauth2_callback_url())
            |> Client.authorize_url!(authorize_params)

          conn
          |> put_session(:custom_oauth2_organization_id, organization_id)
          |> put_session(:custom_oauth2_state, state)
          |> redirect(external: url)
        else
          _ ->
            raise UnauthorizedError,
                  dgettext("dashboard", "Failed to authenticate with the custom OAuth2 provider.")
        end

      _ ->
        raise UnauthorizedError,
              dgettext("dashboard", "Failed to authenticate with the custom OAuth2 provider.")
    end
  end

  def custom_oauth2_callback(conn, _params) do
    case {get_session(conn, :custom_oauth2_organization_id), get_session(conn, :custom_oauth2_state)} do
      {organization_id, state} when not is_nil(organization_id) and not is_nil(state) ->
        if conn.params["state"] != state do
          raise UnauthorizedError,
                dgettext("dashboard", "Failed to authenticate with the custom OAuth2 provider.")
        end

        with {:ok, %Organization{} = organization} <- Accounts.get_organization_by_id(organization_id),
             {:ok, config} <- CustomOAuth2.config_for_organization(organization),
             {:ok, auth} <- custom_oauth2_auth(conn, config) do
          conn
          |> delete_session(:custom_oauth2_organization_id)
          |> delete_session(:custom_oauth2_state)
          |> complete_oauth_callback(auth)
        else
          {:error, reason} ->
            log(:error, "Failed custom OAuth2 callback: #{inspect(reason)}")

            raise UnauthorizedError,
                  dgettext("dashboard", "Failed to authenticate with the custom OAuth2 provider.")

          _ ->
            raise UnauthorizedError,
                  dgettext("dashboard", "Failed to authenticate with the custom OAuth2 provider.")
        end

      _ ->
        raise UnauthorizedError,
              dgettext("dashboard", "Failed to authenticate with the custom OAuth2 provider.")
    end
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

  def okta_callback(conn, params) do
    log(:info, "Starting Okta callback with params: #{inspect(params)}")
    session_data = get_session(conn)
    log(:info, "Session data: #{inspect(session_data)}")

    case session_data do
      %{"okta_organization_id" => organization_id} ->
        log(:info, "Successfully extracted organization_id from session: #{organization_id}")

        case Accounts.get_organization_by_id(organization_id) do
          {:ok, %Organization{} = organization} ->
            log(:info, "Successfully found organization: #{inspect(organization.id)}")

            case Okta.config_for_organization(organization) do
              {:ok, config} ->
                log(
                  :info,
                  "Successfully retrieved Okta config for organization: #{organization.id}, domain: #{config.domain}"
                )

                conn
                |> Ueberauth.run_callback(
                  :okta,
                  {
                    Ueberauth.Strategy.Okta,
                    [
                      client_id: config.client_id,
                      client_secret: config.client_secret,
                      site: "https://#{config.domain}"
                    ]
                  }
                )
                |> callback(params)

              error ->
                log(
                  :error,
                  "Failed to get Okta config for organization #{organization.id}: #{inspect(error)}"
                )

                raise UnauthorizedError,
                      dgettext("dashboard", "Failed to authenticate with Okta.")
            end

          error ->
            log(
              :error,
              "Failed to find organization with id #{organization_id}: #{inspect(error)}"
            )

            raise UnauthorizedError,
                  dgettext("dashboard", "Failed to authenticate with Okta.")
        end

      error ->
        log(
          :error,
          "Failed to extract organization_id from session: #{inspect(session_data)}, error: #{inspect(error)}"
        )

        raise UnauthorizedError,
              dgettext("dashboard", "Failed to authenticate with Okta.")
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

  defp okta_strategy_options(config, params) do
    strategy_options = [
      client_id: config.client_id,
      client_secret: config.client_secret,
      site: "https://#{config.domain}"
    ]

    case params["login_hint"] do
      login_hint when is_binary(login_hint) ->
        default_oauth2_params = [scope: "openid email profile"]
        oauth2_params = Keyword.put(default_oauth2_params, :login_hint, login_hint)
        Keyword.put(strategy_options, :oauth2_params, oauth2_params)

      _ ->
        strategy_options
    end
  end

  defp custom_oauth2_client(config, redirect_uri) do
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
    |> Client.put_serializer("application/json", Jason)
  end

  defp custom_oauth2_auth(conn, config) do
    params = [code: conn.params["code"]]

    with {:ok, %Client{token: token} = client} <-
           Client.get_token(custom_oauth2_client(config, custom_oauth2_callback_url()), params),
         {:ok, %{status_code: 200, body: userinfo}} <- Client.get(client, config.user_info_url) do
      {:ok, build_custom_oauth2_auth(token, userinfo, config.provider_organization_id)}
    else
      {:ok, %{status_code: status_code, body: body}} -> {:error, {:userinfo_request_failed, status_code, body}}
      {:error, reason} -> {:error, reason}
      error -> {:error, error}
    end
  end

  defp build_custom_oauth2_auth(token, userinfo, provider_organization_id) do
    name = userinfo["name"] || userinfo["preferred_username"] || userinfo["email"] || userinfo["sub"]

    %Auth{
      provider: :custom_oauth2,
      strategy: AuthCode,
      uid: userinfo["sub"] || userinfo["id"] || userinfo["email"],
      info: %Info{
        name: name,
        first_name: userinfo["given_name"],
        last_name: userinfo["family_name"],
        nickname: userinfo["preferred_username"],
        email: userinfo["email"]
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

  defp custom_oauth2_callback_url, do: TuistWeb.Endpoint.url() <> ~p"/users/auth/custom_oauth2/callback"

  defp maybe_put_login_hint(params, login_hint) when is_binary(login_hint) and login_hint != "" do
    Keyword.put(params, :login_hint, login_hint)
  end

  defp maybe_put_login_hint(params, _login_hint), do: params
end
