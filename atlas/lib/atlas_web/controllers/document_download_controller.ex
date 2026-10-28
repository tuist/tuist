defmodule AtlasWeb.DocumentDownloadController do
  @moduledoc """
  Opens a stored document for an authenticated executive.

  Returns a redirect to a short-lived signed object link when the object store
  supports one, and otherwise streams the bytes directly. The Atlas link itself
  is stable, so it can be shared by agents and the Slack bot; the signing
  happens fresh on each request.
  """

  use AtlasWeb, :controller

  alias Atlas.Documents
  alias Atlas.Documents.Document
  alias Atlas.Documents.Storage
  alias Atlas.Users
  alias AtlasWeb.DocumentLinks

  def show(conn, %{"id" => id} = params) do
    user = conn.assigns[:current_user]

    cond do
      not Users.has_scope?(user, "documents:read") ->
        conn
        |> put_status(:forbidden)
        |> text("Documents are only available to executives.")

      document = Documents.get_document(id, pages: false) ->
        if canonical_download_path?(params, document) do
          open_document(conn, document)
        else
          redirect(conn, to: DocumentLinks.download_path(document))
        end

      true ->
        conn
        |> put_status(:not_found)
        |> text("Document not found.")
    end
  end

  defp canonical_download_path?(%{"filename" => filename}, %Document{} = document) do
    filename == DocumentLinks.download_filename(document)
  end

  defp canonical_download_path?(_params, %Document{}), do: false

  defp open_document(conn, %Document{} = document) do
    case Storage.presigned_get_url(document.storage_key, expires_in: 300) do
      {:ok, url} ->
        redirect(conn, external: url)

      {:error, _reason} ->
        stream_document(conn, document)
    end
  end

  defp stream_document(conn, %Document{} = document) do
    case Storage.get_object(document.storage_key) do
      {:ok, %{body: body}} ->
        conn
        |> put_resp_content_type(document.content_type || "application/octet-stream")
        |> put_resp_header(
          "content-disposition",
          ~s(inline; filename="#{DocumentLinks.download_filename(document)}")
        )
        |> send_resp(200, body)

      {:error, _reason} ->
        conn
        |> put_status(:not_found)
        |> text("Document file is unavailable.")
    end
  end
end
