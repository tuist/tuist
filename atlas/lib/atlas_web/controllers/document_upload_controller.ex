defmodule AtlasWeb.DocumentUploadController do
  @moduledoc """
  Receives direct-to-storage document uploads when the `Local` storage backend
  is in use. The URL is minted by `Atlas.Documents.Storage.Local.presigned_put_url/2`
  and carries a Phoenix-signed token binding the storage key, the required
  `Content-Type`, and the expiry.

  In production the `Atlas.ObjectStorage` backend returns real S3 presigned
  URLs and this controller is never involved.
  """

  use AtlasWeb, :controller

  alias Atlas.Documents.Storage
  alias Atlas.Documents.Storage.Local

  @max_body_bytes 100 * 1024 * 1024

  def put(conn, %{"token" => token}) do
    with {:ok, %{key: key, content_type: bound_content_type}} <-
           Local.verify_upload_token(token),
         :ok <- match_content_type(conn, bound_content_type),
         {:ok, body, conn} <- read_full_body(conn),
         {:ok, _object} <-
           Storage.put_object(key, body, content_type: bound_content_type || content_type(conn)) do
      send_resp(conn, :ok, "")
    else
      {:error, :expired} -> send_resp(conn, :forbidden, "Upload URL expired.")
      {:error, :invalid} -> send_resp(conn, :forbidden, "Invalid upload URL.")
      {:error, :missing} -> send_resp(conn, :forbidden, "Invalid upload URL.")
      {:error, :content_type_mismatch} -> send_resp(conn, :bad_request, "Content-Type header does not match.")
      {:error, :too_large} -> send_resp(conn, :request_entity_too_large, "Upload exceeds size limit.")
      {:error, _reason} -> send_resp(conn, :bad_request, "Upload failed.")
    end
  end

  defp match_content_type(_conn, nil), do: :ok
  defp match_content_type(_conn, ""), do: :ok

  defp match_content_type(conn, bound) do
    if content_type(conn) == bound, do: :ok, else: {:error, :content_type_mismatch}
  end

  defp content_type(conn) do
    conn
    |> get_req_header("content-type")
    |> List.first()
    |> case do
      nil -> nil
      value -> value |> String.split(";") |> List.first() |> String.trim()
    end
  end

  defp read_full_body(conn) do
    case Plug.Conn.read_body(conn, length: @max_body_bytes) do
      {:ok, chunk, conn} -> {:ok, chunk, conn}
      {:more, _chunk, _conn} -> {:error, :too_large}
      {:error, reason} -> {:error, reason}
    end
  end
end
