defmodule TuistWeb.PageController do
  use TuistWeb, :controller

  def home(conn, _params) do
    # The home page is often custom made,
    # so skip the default app layout.
    render(conn, :home, layout: false)
  end

  def ready(conn, _params) do
    conn |> Plug.Conn.send_resp(200, []) |> Plug.Conn.halt()
  end
end
