defmodule TuistWeb.Plugs.CloseConnectionOnErrorPlug do
  @moduledoc """
  Automatically adds `Connection: close` header to all error responses (4xx/5xx).

  This prevents Bandit from trying to drain large request bodies when returning
  early errors, which would otherwise cause body read timeout errors.
  """

  @behaviour Plug

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    register_before_send(conn, fn conn ->
      if conn.status && conn.status >= 400 do
        put_resp_header(conn, "connection", "close")
      else
        conn
      end
    end)
  end
end
