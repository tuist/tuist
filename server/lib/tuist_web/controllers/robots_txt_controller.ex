defmodule TuistWeb.RobotsTxtController do
  use TuistWeb, :controller

  alias TuistWeb.Utilities.RobotsTxt

  def show(conn, _params) do
    conn
    |> put_resp_content_type("text/plain", "utf-8")
    |> send_resp(:ok, RobotsTxt.render())
  end
end
