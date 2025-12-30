defmodule TuistWeb.AuthController do
  @moduledoc """
  Auth controller.
  """

  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Accounts.Organization
  alias Tuist.OAuth.Okta
  alias TuistWeb.Authentication

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

                conn
                |> put_flash(:error, "Failed to authenticate with Okta.")
                |> redirect(to: ~p"/")
                |> halt()
            end

          error ->
            log(
              :error,
              "Failed to find organization with id #{organization_id}: #{inspect(error)}"
            )

            conn
            |> put_flash(:error, "Failed to authenticate with Okta.")
            |> redirect(to: ~p"/")
            |> halt()
        end

      error ->
        log(
          :error,
          "Failed to extract organization_id from params: #{inspect(params)}, error: #{inspect(error)}"
        )

        conn
        |> put_flash(:error, "Failed to authenticate with Okta.")
        |> redirect(to: ~p"/")
        |> halt()
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "You have been logged out!")
    |> clear_session()
    |> redirect(to: ~p"/")
    |> halt()
  end

  def callback(%{assigns: %{ueberauth_failure: failure}} = conn, _params) do
    log(
      :error,
      "Ueberauth failed authenticating: #{inspect(failure)}"
    )

    conn
    |> put_flash(:error, "Failed to authenticate.")
    |> redirect(to: ~p"/")
    |> halt()
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    case Accounts.get_oauth2_identity(auth.provider, auth.uid) do
      {:ok, oauth2_identity} ->
        user = oauth2_identity.user
        oauth_return_url = get_session(conn, :oauth_return_to)

        if oauth_return_url do
          conn
          |> put_session(:user_return_to, oauth_return_url)
          |> delete_session(:oauth_return_to)
          |> Authentication.log_in_user(user)
        else
          Authentication.log_in_user(conn, user)
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
              |> Authentication.log_in_user(existing_user)
            else
              Authentication.log_in_user(conn, existing_user)
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

                conn
                |> put_flash(:error, "Failed to authenticate with Okta.")
                |> redirect(to: ~p"/")
                |> halt()
            end

          error ->
            log(
              :error,
              "Failed to find organization with id #{organization_id}: #{inspect(error)}"
            )

            conn
            |> put_flash(:error, "Failed to authenticate with Okta.")
            |> redirect(to: ~p"/")
            |> halt()
        end

      error ->
        log(
          :error,
          "Failed to extract organization_id from session: #{inspect(session_data)}, error: #{inspect(error)}"
        )

        conn
        |> put_flash(:error, "Failed to authenticate with Okta.")
        |> redirect(to: ~p"/")
        |> halt()
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
            conn
            |> delete_session(:pending_oauth_signup)
            |> put_session(:user_return_to, oauth_return_url)
            |> Authentication.log_in_user(user)
        end

      {:error, _reason} ->
        redirect(conn, to: ~p"/users/log_in")
    end
  end

  def complete_signup(conn, _params) do
    redirect(conn, to: ~p"/users/log_in")
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
end
