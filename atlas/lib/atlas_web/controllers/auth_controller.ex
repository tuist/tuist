defmodule AtlasWeb.AuthController do
  use AtlasWeb, :controller

  alias Atlas.Users

  plug Ueberauth

  def request(conn, _params) do
    conn
    |> put_flash(:error, "Authentication provider not supported.")
    |> redirect(to: ~p"/login")
  end

  def callback(%{assigns: %{ueberauth_failure: _failure}} = conn, _params) do
    conn
    |> put_flash(:error, "Authentication failed. Please try again.")
    |> redirect(to: ~p"/login")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    case Users.find_or_create_user_from_auth(auth) do
      {:ok, user} ->
        conn
        |> put_session(:user_id, user.id)
        |> configure_session(renew: true)
        |> redirect(to: ~p"/")

      {:error, :unauthorized_domain} ->
        domain = Application.fetch_env!(:atlas, :allowed_email_domain)

        conn
        |> put_flash(:error, "Sign-in is restricted to @#{domain} accounts.")
        |> redirect(to: ~p"/login")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Something went wrong creating your account.")
        |> redirect(to: ~p"/login")
    end
  end

  def dev_login(conn, _params) do
    if Application.get_env(:atlas, :dev_routes) do
      case Users.get_user_by_email("test@atlas.dev") do
        nil ->
          conn
          |> put_flash(:error, "Test user not found. Run mix run priv/repo/seeds.exs first.")
          |> redirect(to: ~p"/login")

        user ->
          conn
          |> put_session(:user_id, user.id)
          |> configure_session(renew: true)
          |> redirect(to: ~p"/")
      end
    else
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(404, "Not found")
    end
  end

  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: ~p"/login")
  end
end
