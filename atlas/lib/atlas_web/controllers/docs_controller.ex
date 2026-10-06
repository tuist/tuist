defmodule AtlasWeb.DocsController do
  use AtlasWeb, :controller

  alias AtlasWeb.DocsHTML

  def show(conn, params) do
    slug = params |> Map.get("path", []) |> Enum.join("/")

    case DocsHTML.page(slug) do
      nil ->
        conn |> put_resp_content_type("text/plain") |> send_resp(404, "Documentation page not found")

      page ->
        if conn.private[:docs_markdown_requested] do
          conn |> put_resp_content_type("text/markdown") |> send_resp(200, page.markdown)
        else
          render(conn, :show, page: page, pages: DocsHTML.pages(), slug: slug, page_title: page.title)
        end
    end
  end

  def markdown(conn, params) do
    slug = params |> Map.get("path", []) |> Enum.join("/")

    case DocsHTML.page(slug) do
      nil -> conn |> put_resp_content_type("text/plain") |> send_resp(404, "Documentation page not found")
      page -> conn |> put_resp_content_type("text/plain") |> send_resp(200, page.markdown)
    end
  end
end
