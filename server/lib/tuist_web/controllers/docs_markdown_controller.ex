defmodule TuistWeb.DocsMarkdownController do
  @moduledoc false
  use TuistWeb, :controller

  alias Tuist.Docs
  alias Tuist.Docs.Paths

  def show(conn, %{"locale" => locale} = params) do
    path_segments = Map.get(params, "path", [])

    case Docs.get_page(Paths.slug(locale, path_segments)) do
      nil ->
        send_resp(conn, :not_found, "Page not found")

      page ->
        conn
        |> put_resp_content_type("text/plain", "utf-8")
        |> send_resp(:ok, page.markdown)
    end
  end
end
