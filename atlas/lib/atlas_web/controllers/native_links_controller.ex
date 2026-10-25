defmodule AtlasWeb.NativeLinksController do
  @moduledoc """
  Public, credential-free native link endpoints: the app association files and the
  `/open` landing page. None of them reads a session, a user, or a record.
  """
  use AtlasWeb, :controller

  alias AtlasWeb.NativeLinks
  alias AtlasWeb.NativeLinks.Config

  @android_package "dev.tuist.atlas"

  def apple_app_site_association(conn, _params) do
    case Config.apple_app_ids() do
      [] ->
        not_found(conn)

      app_ids ->
        components = Enum.map(NativeLinks.claimed_paths(), &%{"/" => &1})
        association(conn, %{applinks: %{details: [%{appIDs: app_ids, components: components}]}})
    end
  end

  def asset_links(conn, _params) do
    case Config.android_sha256_fingerprints() do
      [] ->
        not_found(conn)

      fingerprints ->
        association(conn, [
          %{
            relation: ["delegate_permission/common.handle_all_urls"],
            target: %{
              namespace: "android_app",
              package_name: @android_package,
              sha256_cert_fingerprints: fingerprints
            }
          }
        ])
    end
  end

  # Only the path selects a destination. Query arguments are ignored entirely so
  # `?id=` or `?screen=` can never add a record, change the screen, or reach a link.
  def open(conn, _params) do
    segments = [conn.path_params["screen"] | List.wrap(conn.path_params["id"])]

    case NativeLinks.for_open(segments) do
      nil ->
        conn
        |> put_resp_header("x-robots-tag", "noindex, nofollow")
        |> not_found()

      destination ->
        conn
        |> put_format("html")
        |> put_resp_header("cache-control", "public, max-age=300")
        |> put_resp_header("x-robots-tag", "noindex, nofollow")
        |> put_root_layout(html: {AtlasWeb.NativeLinksHTML, :root})
        |> put_layout(false)
        |> render(:open,
          page_title: gettext("Open in Atlas"),
          destination: destination,
          native_url: NativeLinks.native_url(destination),
          browser_path: NativeLinks.browser_path(destination)
        )
    end
  end

  defp association(conn, body) do
    conn
    |> put_resp_content_type("application/json", nil)
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> send_resp(200, JSON.encode!(body))
  end

  defp not_found(conn) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(404, "Not found")
  end
end
