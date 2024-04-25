defmodule TuistCloudWeb.AuthController do
  @moduledoc """
  Auth controller responsible for handling Ueberauth responses
  """

  use TuistCloudWeb, :controller
  alias TuistCloud.Accounts

  plug Ueberauth

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "You have been logged out!")
    |> clear_session()
    |> redirect(to: ~p"/v2")
  end

  def callback(%{assigns: %{ueberauth_failure: _failure}} = conn, _params) do
    conn
    |> put_flash(:error, "Failed to authenticate.")
    |> redirect(to: ~p"/v2")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    user = Accounts.find_or_create_user_from_oauth2(auth)

    conn
    |> put_flash(:info, "Successfully authenticated.")
    |> TuistCloudWeb.UserAuth.log_in_user(user)
    |> redirect(to: ~p"/v2")
  end
end
