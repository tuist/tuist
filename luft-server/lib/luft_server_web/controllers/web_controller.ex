defmodule LuftServerWeb.WebController do
  @moduledoc """
  Serves the GPUI web edge's page under `/app` and returns JSON not-found
  responses for every other path outside the headless API.
  """
  use LuftServerWeb, :controller

  def show(conn, _params) do
    conn
    |> put_status(:not_found)
    |> json(%{error: "not_found"})
  end

  @doc """
  The page for `/app/` and its client-side paths. Relative URLs need the
  trailing slash, so `/app` redirects. A missing file under `/app` is a 404,
  never the page, and so is a server built without the web edge.
  """
  def app(%{request_path: "/app"} = conn, _params) do
    query = if conn.query_string == "", do: "", else: "?" <> conn.query_string
    redirect(conn, to: "/app/" <> query)
  end

  def app(conn, params) do
    index = Application.app_dir(:luft_server, "priv/static/app/index.html")
    file? = params |> Map.get("path", []) |> List.last("") |> String.contains?(".")

    if not file? and File.regular?(index) do
      conn
      |> put_resp_content_type("text/html")
      |> put_resp_header("cache-control", "no-cache")
      |> send_file(200, index)
    else
      show(conn, params)
    end
  end
end
