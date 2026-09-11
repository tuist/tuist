defmodule TuistWeb.LlmsTxtController do
  use TuistWeb, :controller

  alias TuistWeb.Utilities.LlmsTxt

  def show(conn, _params) do
    conn
    |> put_resp_content_type("text/plain", "utf-8")
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> send_resp(:ok, LlmsTxt.render())
  end
end
