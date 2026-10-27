defmodule AtlasWeb.Plugs.DemoGuard do
  @moduledoc """
  Denies non-dashboard surfaces in demo mode before parsing request bodies.
  WebSocket and long-poll transport events are separately gated by DemoLiveGuard.
  """

  import Plug.Conn

  alias Atlas.Demo

  def init(opts), do: opts

  def call(conn, _opts) do
    if Demo.enabled?() do
      conn = conn |> put_resp_header("x-tuist-public", "1") |> put_resp_header("x-robots-tag", "noindex, nofollow")

      cond do
        conn.request_path in ["/live/websocket", "/live/longpoll"] and conn.method in ["GET", "POST"] ->
          conn

        conn.method in ["GET", "HEAD"] and Demo.public_path?(conn.request_path) ->
          conn

        true ->
          conn
          |> put_resp_content_type("text/plain")
          |> send_resp(403, "This action is unavailable in the read-only Atlas demo.")
          |> halt()
      end
    else
      conn
    end
  end
end
