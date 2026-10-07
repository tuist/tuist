defmodule TuistWeb.MarketingMarkdownController do
  use TuistWeb, :controller

  alias TuistWeb.Utilities.MarkdownResponse
  alias TuistWeb.Utilities.MarketingMarkdown

  def show(conn, params) do
    path = "/" <> Enum.join(Map.get(params, "path", []), "/")

    respond(conn, MarketingMarkdown.get(path))
  end

  def source(conn, %{"path" => segments}) do
    respond(conn, MarketingMarkdown.source("/" <> Enum.join(segments, "/")))
  end

  defp respond(conn, content) do
    case content do
      nil ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> send_resp(:not_found, "Page not found")

      markdown ->
        conn
        |> put_resp_header("content-language", "en")
        |> put_resp_header("cache-control", "public, max-age=3600")
        |> MarkdownResponse.prepare(markdown)
        |> send_resp(:ok, markdown)
    end
  end
end
