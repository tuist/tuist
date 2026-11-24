defmodule LuftServerWeb.Auth do
  @moduledoc """
  The session cookie: an opaque token naming a row in `LuftServer.Sessions`,
  set as OAuth 2.0 for Browser-Based Applications (RFC 10017, 6.1.3.2) asks of
  a backend for frontend: `Secure`, `HttpOnly`, `SameSite=Strict`, path `/`,
  no `Domain`, and the `__Host-Http-` prefix, so no other `*.luft.work` host
  and no script can set or read it. Development serves plain HTTP, where
  browsers refuse `__Host-` cookies, so it drops the prefix.
  """
  import Plug.Conn

  def cookie_name, do: if(secure?(), do: "__Host-Http-luft_session", else: "luft_session")

  def put_session_cookie(conn, token) do
    put_resp_cookie(conn, cookie_name(), token,
      http_only: true,
      secure: secure?(),
      same_site: "Strict",
      path: "/",
      max_age: 30 * 24 * 60 * 60
    )
  end

  def delete_session_cookie(conn),
    do: delete_resp_cookie(conn, cookie_name(), secure: secure?(), path: "/")

  def session_token(conn) do
    conn |> fetch_cookies() |> Map.get(:cookies) |> Map.get(cookie_name())
  end

  defp secure?, do: Application.get_env(:luft_server, :secure_cookies, true)
end
