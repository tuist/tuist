defmodule TuistWeb.MarketingMarkdownController do
  use TuistWeb, :controller

  alias TuistWeb.Utilities.MarkdownResponse
  alias TuistWeb.Utilities.MarketingMarkdown

  def show(conn, params) do
    path = "/" <> Enum.join(Map.get(params, "path", []), "/")

    respond(conn, MarketingMarkdown.get(path), path)
  end

  def source(conn, %{"path" => segments}) do
    respond(conn, MarketingMarkdown.source("/" <> Enum.join(segments, "/")), nil)
  end

  defp respond(conn, content, path) do
    case content do
      nil ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> send_resp(:not_found, "Page not found")

      markdown ->
        conn
        |> put_canonical(path)
        |> put_resp_header("content-language", "en")
        |> put_resp_header("cache-control", "public, max-age=3600")
        |> MarkdownResponse.prepare(markdown)
        |> send_resp(:ok, markdown)
    end
  end

  defp put_canonical(conn, nil), do: conn

  defp put_canonical(conn, path) do
    url = Tuist.Environment.app_url(path: path)
    put_resp_header(conn, "link", ~s(<#{url}>; rel="canonical"))
  end
end
