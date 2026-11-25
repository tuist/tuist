defmodule AtlasWeb.DocumentSignedDownloadController do
  @moduledoc """
  Serves a stored document to whoever presents a short-lived signed token from
  `get_document_download_url` or `save_my_gmail_attachment`. The token is the auth, like
  Slack file and contract template links, because the agent's HTTP client has
  no Atlas session. The token names the user it was issued to, and that user
  must still have document access when the link is opened.
  """

  use AtlasWeb, :controller

  alias Atlas.Documents
  alias Atlas.Documents.Document
  alias Atlas.Documents.Storage
  alias Atlas.Users
  alias Atlas.Users.User
  alias AtlasWeb.DocumentLinks

  def show(conn, %{"id" => id, "token" => token}) when is_binary(token) do
    with {:ok, %{"document_id" => ^id, "user_id" => user_id}} <- DocumentLinks.verify_signed_download(token),
         %User{} = user <- Users.get_user(user_id),
         true <- Users.has_scope?(user, "documents:read") || {:error, :forbidden},
         %Document{} = document <- Documents.get_document(id, pages: false),
         {:ok, %{body: body}} <- Storage.get_object(document.storage_key) do
      conn
      |> put_resp_content_type(document.content_type || "application/octet-stream", nil)
      |> put_resp_header(
        "content-disposition",
        ~s(attachment; filename="#{DocumentLinks.download_filename(document)}")
      )
      |> put_resp_header("cache-control", "no-store")
      |> send_resp(200, body)
    else
      {:error, :expired} ->
        send_resp(conn, 410, "This download link has expired. Call get_document_download_url again.")

      {:error, :forbidden} ->
        send_resp(conn, 403, "Documents are only available to executives.")

      _other ->
        send_resp(conn, 404, "Not Found")
    end
  end

  def show(conn, _params), do: send_resp(conn, 404, "Not Found")
end
