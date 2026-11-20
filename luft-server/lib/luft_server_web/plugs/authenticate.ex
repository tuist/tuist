defmodule LuftServerWeb.Plugs.Authenticate do
  @moduledoc "Resolves the Luft session from a native bearer, machine credential or browser cookie."
  @behaviour Plug

  import Plug.Conn

  alias LuftServer.NativeAuth
  alias LuftServer.RunnerCredentials
  alias LuftServer.Sessions
  alias LuftServerWeb.Auth

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    conn =
      case get_req_header(conn, "authorization") do
        ["Bearer " <> token] -> authenticate_bearer(conn, token)
        [] -> assign(conn, :session, conn |> Auth.session_token() |> Sessions.get())
        _ -> assign(conn, :session, nil)
      end

    case conn.assigns.session do
      nil -> conn |> Auth.delete_session_cookie() |> unauthorized()
      _session -> conn
    end
  end

  defp authenticate_bearer(conn, token) do
    if String.starts_with?(conn.request_path, "/api/thread-runner/") do
      case RunnerCredentials.resolve(token) do
        {:ok, session, upstream} ->
          conn |> assign(:session, session) |> assign(:runner_token, upstream)

        :error ->
          assign(conn, :session, nil)
      end
    else
      assign(conn, :session, NativeAuth.resolve_bearer(token))
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
