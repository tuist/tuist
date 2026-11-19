defmodule LuftServerWeb.Plugs.Authenticate do
  @moduledoc "Assigns `:session` from the session cookie, or answers 401."
  @behaviour Plug

  import Plug.Conn

  alias LuftServer.Sessions
  alias LuftServerWeb.Auth

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    case conn |> Auth.session_token() |> Sessions.get() do
      nil -> conn |> Auth.delete_session_cookie() |> unauthorized()
      session -> assign(conn, :session, session)
    end
  end

  def unauthorized(conn) do
    conn
    |> put_status(:unauthorized)
    |> Phoenix.Controller.json(%{
      error: "unauthenticated",
      login_url: LuftServer.Config.public_url() <> "/auth/login"
    })
    |> halt()
  end
end
