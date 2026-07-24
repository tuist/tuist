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
      {:versioned, source_path, key} ->
        serve(conn, key, fn -> resolve.(source_path) end, :immutable)

      {:unversioned, source_path} ->
        serve_unversioned(conn, source_path, resolve)
    end
  end

  # Unversioned URLs are the ones already shared on social platforms, from
  # before image paths carried a content key. They serve the image directly
  # rather than redirecting to the versioned path: a social crawler gets the
  # card in one hop, with no dependency on how it handles redirects. The URL
  # cannot change when the content does, so it is cached with revalidation
  # instead of the immutable header the versioned path gets, and the content key
  # is the entity tag so a revalidation is a cheap 304 until the image changes.
  defp serve_unversioned(conn, source_path, resolve) do
    case resolve.(source_path) do
      {:ok, spec} -> serve(conn, spec.key, fn -> {:ok, spec} end, :revalidated)
      :error -> not_found(conn)
    end
  end

  defp serve(conn, key, resolve, caching) do
    case OpenGraphImages.ensure_available(key, resolve) do
      :ok -> send_image(conn, key, caching)
      {:transient, image} -> serve_transient(conn, image)
      {:error, reason} when reason in [:not_found, :stale_version] -> not_found(conn)
      {:error, reason} -> unavailable(conn, reason)
    end
  end

  defp send_image(conn, key, caching) do
    etag = ~s("#{key}")

    if etag in get_req_header(conn, "if-none-match") do
      conn
      |> put_image_headers(etag, caching)
      |> send_resp(:not_modified, "")
    else
      # The image is fetched before any header is committed so a storage
      # failure degrades to a 503 the caller will retry, rather than a
      # truncated body under a long-lived cache header.
      case OpenGraphImages.fetch(key) do
        {:ok, image} ->
          conn
          |> put_image_headers(etag, caching)
          |> send_resp(:ok, image)

        {:error, reason} ->
          unavailable(conn, reason)
      end
    end
  end

  defp put_image_headers(conn, etag, caching) do
    conn
    |> put_resp_content_type("image/jpeg", nil)
    |> put_resp_header("cache-control", cache_control(caching))
    |> put_resp_header("etag", etag)
    |> put_resp_header("x-content-type-options", "nosniff")
  end

  # A versioned URL only ever names one image, so it can be cached forever.
  # An unversioned one names whatever the page currently renders to, so it is
  # revalidated, and served stale while that happens to keep crawlers off the
  # render path.
  defp cache_control(:immutable), do: "public, max-age=31536000, immutable"
  defp cache_control(:revalidated), do: "public, max-age=3600, stale-while-revalidate=86400"

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
