defmodule LuftServerWeb.Plugs.RequireSameOriginWrites do
  @moduledoc """
  Cross-site request forgery protection for the cookie-authenticated API
  (RFC 10017, 6.1.3.3). The web app and this server share one origin, so
  every non-safe request must carry an `Origin` header naming it; browsers
  set it on every POST, and pages cannot forge it. `SameSite=Strict` alone
  would still let a sibling `*.luft.work` host forge requests.
  """
  @behaviour Plug

  import Plug.Conn

  alias LuftServer.Config

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{method: method} = conn, _opts) when method in ["GET", "HEAD", "OPTIONS"],
    do: conn

  def call(conn, _opts) do
    origin = conn |> get_req_header("origin") |> List.first()

    # Bearer credentials are explicit, not ambient cookies. Authenticate still
    # validates them; an invalid bearer must never fall back to a cookie.
    if match?(["Bearer " <> _], get_req_header(conn, "authorization")) or
         origin == Config.public_url() do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> Phoenix.Controller.json(%{error: "forbidden_origin"})
      |> halt()
    end
  end
end
