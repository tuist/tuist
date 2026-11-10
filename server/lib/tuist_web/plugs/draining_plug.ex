defmodule TuistWeb.Plugs.DrainingPlug do
  @moduledoc """
  While the server drains (`TuistWeb.Draining`), answers HTTP/1.x requests with
  `Connection: close`, so each kept-alive connection closes after a complete
  response and the client opens its next one on a pod that keeps serving.
  HTTP/2 forbids the header, so HTTP/2 connections are left to the endpoint's
  shutdown.
  """

  @behaviour Plug

  import Plug.Conn

  alias TuistWeb.Draining

  @http1 [:"HTTP/1", :"HTTP/1.0", :"HTTP/1.1"]

  def init(opts), do: opts

  def call(conn, _opts) do
    if get_http_protocol(conn) in @http1 do
      register_before_send(conn, &close_while_draining/1)
    else
      conn
    end
  end

  defp close_while_draining(%{status: status} = conn) when is_integer(status) and status >= 200 do
    if Draining.draining?(), do: put_resp_header(conn, "connection", "close"), else: conn
  end

  defp close_while_draining(conn), do: conn
end
