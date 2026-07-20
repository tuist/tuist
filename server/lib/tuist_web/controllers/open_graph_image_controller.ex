defmodule TuistWeb.OpenGraphImageController do
  use TuistWeb, :controller

  alias Tuist.Docs.OgImage, as: DocsImage
  alias Tuist.Marketing.OpenGraphImage, as: MarketingImage
  alias Tuist.OpenGraphImages

  require Logger

  def marketing(conn, _params), do: show(conn, &MarketingImage.resolve/1)
  def docs(conn, _params), do: show(conn, &DocsImage.resolve/1)

  defp show(conn, resolve) do
    case OpenGraphImages.parse_path(conn.request_path) do
      {:versioned, source_path, key} -> serve_versioned(conn, source_path, key, resolve)
      {:unversioned, source_path} -> redirect_to_versioned(conn, source_path, resolve)
    end
  end

  defp redirect_to_versioned(conn, source_path, resolve) do
    case resolve.(source_path) do
      {:ok, spec} ->
        conn
        |> put_resp_header("cache-control", "public, max-age=60")
        |> redirect(to: OpenGraphImages.versioned_path(source_path, spec.key), status: 302)

      :error ->
        not_found(conn)
    end
  end

  defp serve_versioned(conn, source_path, key, resolve) do
    result =
      try do
        OpenGraphImages.ensure_available(key, fn -> resolve.(source_path) end)
      rescue
        error -> {:error, error}
      catch
        # A GenServer.call timeout while the browser pool starts (and any
        # other exit bubbling up from generation) arrives as an exit, which
        # `rescue` does not catch; handle it so the request degrades to 503
        # instead of crashing with a 500.
        :exit, reason -> {:error, reason}
      end

    case result do
      :ok -> send_image(conn, key)
      {:transient, image} -> serve_transient(conn, image)
      {:error, reason} when reason in [:not_found, :stale_version] -> not_found(conn)
      {:error, reason} -> unavailable(conn, reason)
    end
  end

  defp send_image(conn, key) do
    etag = ~s("#{key}")

    if etag in get_req_header(conn, "if-none-match") do
      conn
      |> put_immutable_image_headers(etag)
      |> send_resp(:not_modified, "")
    else
      # The image is fetched before any header is committed so a storage
      # failure degrades to a 503 the caller will retry, rather than a
      # truncated body under an immutable, year-long cache header.
      case OpenGraphImages.fetch(key) do
        {:ok, image} ->
          conn
          |> put_immutable_image_headers(etag)
          |> send_resp(:ok, image)

        {:error, reason} ->
          unavailable(conn, reason)
      end
    end
  end

  defp put_immutable_image_headers(conn, etag) do
    conn
    |> put_resp_content_type("image/jpeg", nil)
    |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
    |> put_resp_header("etag", etag)
    |> put_resp_header("x-content-type-options", "nosniff")
  end

  defp serve_transient(conn, image) do
    conn
    |> put_resp_content_type("image/jpeg", nil)
    |> put_resp_header("cache-control", "public, max-age=60")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> send_resp(:ok, image)
  end

  defp not_found(conn) do
    conn
    |> put_resp_header("cache-control", "public, max-age=60")
    |> send_resp(:not_found, "")
  end

  defp unavailable(conn, reason) do
    Logger.error("Runtime Open Graph image generation failed: #{inspect(reason)}")
    send_resp(conn, :service_unavailable, "")
  end
end
