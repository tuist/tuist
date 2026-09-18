defmodule AtlasWeb.PagesServeController do
  @moduledoc """
  Serves the static objects that back a Pages site. Reached only through
  `AtlasWeb.Plugs.PagesSubdomain`, so by the time we get here the request is
  already scoped to a single-label subdomain and the user is authenticated.

  We stream the object body straight from object storage in memory. Static
  sites hosted here are expected to be small (dashboards, prototypes, memos),
  and Shopify's Quick runs its entire fleet on a single VM under the same
  shape, so we can start here and revisit if a site ever needs its own CDN.
  """

  use AtlasWeb, :controller

  alias Atlas.Engineering.Pages

  def init(opts), do: opts

  def call(conn, opts) do
    slug = opts[:slug] || conn.assigns[:pages_slug]
    action(conn, slug, conn.path_info)
  end

  defp action(conn, nil, _path_info), do: send_resp(conn, 404, "")

  defp action(conn, slug, path_info) do
    case Pages.get_page_by_slug(slug) do
      nil ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(404, not_found_html("This page has not been deployed yet."))

      page ->
        request_path = "/" <> Enum.join(path_info, "/")

        case Pages.fetch_object(page, request_path) do
          {:ok, %{body: body, content_type: content_type}} ->
            conn
            |> put_resp_header("cache-control", "private, max-age=60")
            |> put_resp_header("x-atlas-pages-slug", page.slug)
            |> put_resp_header("content-type", content_type || "application/octet-stream")
            |> send_resp(200, body)

          {:error, :not_found} ->
            conn
            |> put_resp_content_type("text/html")
            |> send_resp(404, not_found_html("File not found in this deploy."))
        end
    end
  end

  defp not_found_html(reason) do
    """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <title>Not found</title>
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <style>
          body { font-family: system-ui, -apple-system, "Segoe UI", sans-serif; margin: 4rem auto; max-width: 32rem; color: #24292f; padding: 0 1.5rem; }
          h1 { font-size: 1.25rem; margin-bottom: 0.5rem; }
          p { color: #57606a; }
          code { background: #f6f8fa; padding: 0.15rem 0.35rem; border-radius: 4px; }
        </style>
      </head>
      <body>
        <h1>Not found</h1>
        <p>#{Phoenix.HTML.html_escape(reason) |> Phoenix.HTML.safe_to_string()}</p>
        <p>Head back to <a href="https://atlas.tuist.dev/engineering/pages">Atlas Pages</a> to redeploy or pick a different site.</p>
      </body>
    </html>
    """
  end
end
