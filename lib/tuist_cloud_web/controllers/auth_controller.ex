defmodule TuistCloudWeb.AuthController do
  @moduledoc """
  Auth controller.
  """

  use TuistCloudWeb, :controller
  alias TuistCloud.Accounts
  alias TuistCloudWeb.Authentication

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "You have been logged out!")
    |> clear_session()
    |> redirect(to: ~p"/")
  end

  def callback(%{assigns: %{ueberauth_failure: _failure}} = conn, _params) do
    conn
    |> put_flash(:error, "Failed to authenticate.")
    |> redirect(to: ~p"/")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    user = Accounts.find_or_create_user_from_oauth2(auth)

    conn
    |> put_flash(:info, "Successfully authenticated.")
    |> Authentication.log_in_user(user)
  end

  def authenticate(conn, params) do
    device_code = params["device_code"]

    if is_nil(Accounts.get_device_code(device_code)) do
      Accounts.create_device_code(device_code)
    end

    conn
    |> redirect(to: ~p"/auth/cli/success/#{device_code}")
  end
end
