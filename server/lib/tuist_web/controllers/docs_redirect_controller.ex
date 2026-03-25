defmodule TuistWeb.DocsRedirectController do
  @moduledoc false
  use TuistWeb, :controller

  alias Tuist.Docs.Paths

  def show(conn, params) do
    locale = Map.get(params, "locale", "en")
    path_segments = Map.get(params, "path", [])

    redirect_path =
      locale
      |> Paths.public_path(path_segments)
      |> append_query_string(conn.query_string)

    conn
    |> put_status(:moved_permanently)
    |> redirect(to: redirect_path)
  end

  defp append_query_string(path, ""), do: path
  defp append_query_string(path, query_string), do: "#{path}?#{query_string}"
end
