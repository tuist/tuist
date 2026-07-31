defmodule TuistWeb.OpenGraphImageController do
  use TuistWeb, :controller

  alias Tuist.OpenGraphImages
  alias Tuist.OpenGraphImageTemplates
  alias TuistWeb.Helpers.OpenGraph

  require Logger

  def show(conn, %{"key" => filename, "signature" => signature} = params) do
    image_params = Map.drop(params, ["key", "signature"])

    with {:ok, key} <- parse_key(filename),
         :ok <- OpenGraph.verify_image_params(image_params, signature),
         {:ok, %{key: ^key} = spec} <- OpenGraphImageTemplates.spec(image_params) do
      serve(conn, spec)
    else
      _ -> not_found(conn)
    end
  end

  def show(conn, _params), do: not_found(conn)

  defp serve(conn, %{key: key} = spec) do
    case OpenGraphImages.ensure_available(key, fn -> {:ok, spec} end) do
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
      |> put_image_headers(etag)
      |> send_resp(:not_modified, "")
    else
      # The image is fetched before any header is committed so a storage
      # failure degrades to a 503 the caller will retry, rather than a
      # truncated body under a long-lived cache header.
      case OpenGraphImages.fetch(key) do
        {:ok, image} ->
          conn
          |> put_image_headers(etag)
          |> send_resp(:ok, image)

        {:error, reason} ->
          unavailable(conn, reason)
      end
    end
  end

  defp put_image_headers(conn, etag) do
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

  defp parse_key(filename) do
    case Regex.run(~r/\A([0-9a-f]{64})\.jpg\z/, filename, capture: :all_but_first) do
      [key] -> {:ok, key}
      _ -> :error
    end
  end
end
