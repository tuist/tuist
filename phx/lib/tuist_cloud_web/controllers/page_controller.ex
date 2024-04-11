defmodule TuistCloudWeb.PageController do
  use TuistCloudWeb, :controller

  def ready(conn, _params) do
    conn |> Plug.Conn.send_resp(200, []) |> Plug.Conn.halt()
  end
end
