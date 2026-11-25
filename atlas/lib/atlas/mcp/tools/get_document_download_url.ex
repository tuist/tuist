defmodule Atlas.MCP.Tools.GetDocumentDownloadUrl do
  @moduledoc """
  Returns a short-lived signed link to a stored document's original file, so an
  agent whose HTTP client has no Atlas session can download a `.docx`, `.zip` or
  other upload to edit it. `get_document` is a frozen workflow contract, so the
  link is its own tool rather than an extra field there.
  """

  use Atlas.MCP.Tool,
    name: "get_document_download_url",
    schema: %{
      "type" => "object",
      "required" => ["document_id"],
      "properties" => %{"document_id" => %{"type" => "string", "description" => "Atlas document id."}},
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "required" => ["document_id", "filename", "content_type", "byte_size", "download_url", "expires_at"],
      "properties" => %{
        "document_id" => %{"type" => "string"},
        "filename" => %{"type" => "string"},
        "content_type" => %{"type" => ["string", "null"]},
        "byte_size" => %{"type" => ["integer", "null"]},
        "download_url" => %{
          "type" => "string",
          "description" => "Returns the original file's bytes without an Atlas session until expires_at."
        },
        "expires_at" => %{"type" => "string"}
      },
      "additionalProperties" => false
    }

  alias Atlas.Documents
  alias Atlas.Documents.Document
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.ManageAccountConnections
  alias AtlasWeb.DocumentLinks

  @impl EMCP.Tool
  def description do
    "Get a short-lived signed download_url for a document's original file, for example a .docx to redline or a .zip " <>
      "to unpack, that works without an Atlas session. Valid for 15 minutes and only while you keep document access; " <>
      "call again for a fresh link. Download it before expires_at and do not share it."
  end

  def execute(conn, %{"document_id" => document_id}) when is_binary(document_id) do
    with true <- ManageAccountConnections.allowed_context?(conn) || {:error, :shared_identity},
         :ok <- Tool.authorize_scope(conn, "documents:read", "Document downloads"),
         {:ok, _uuid} <- Ecto.UUID.cast(document_id),
         %Document{status: status} = document when status != "pending_upload" <-
           Documents.get_document(document_id, pages: false) do
      {:ok,
       %{
         document_id: document.id,
         filename: DocumentLinks.download_filename(document),
         content_type: document.content_type,
         byte_size: document.byte_size,
         download_url: DocumentLinks.signed_download_url(document, Tool.current_user(conn)),
         expires_at: DateTime.to_iso8601(DocumentLinks.signed_download_expires_at())
       }}
    else
      # A signed link works for whoever holds it, so the shared Slack identity,
      # whose replies reach people without document access, never gets one.
      {:error, :shared_identity} -> {:error, "Document download links are unavailable to shared Slack identities."}
      {:error, message} when is_binary(message) -> {:error, message}
      %Document{} -> {:error, "The document has no file yet. Call finalize_document_upload first."}
      _not_found -> {:error, "Document not found."}
    end
  end

  def execute(_conn, _args), do: {:error, "document_id is required."}
end
