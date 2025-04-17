defmodule TuistWeb.AuthController do
  @moduledoc """
  Auth controller.
  """

  use TuistWeb, :controller

  alias Tuist.Accounts
  alias TuistWeb.Authentication

  def request(_conn, _params) do
    raise TuistWeb.Errors.NotFoundError,
          gettext("The authentication URL is not supported")
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "You have been logged out!")
    |> clear_session()
    |> redirect(to: ~p"/")
    |> halt()
  end

  def callback(%{assigns: %{ueberauth_failure: _failure}} = conn, _params) do
    conn
    |> put_flash(:error, "Failed to authenticate.")
    |> redirect(to: ~p"/")
    |> halt()
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    user = Accounts.find_or_create_user_from_oauth2(auth)

    conn
    |> put_flash(:info, "Successfully authenticated.")
    |> Authentication.log_in_user(user)
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
end
