defmodule Atlas.MCP.Tools.FinalizeDocumentUpload do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "finalize_document_upload",
    schema: %{
      "type" => "object",
      "required" => ["document_id"],
      "properties" => %{
        "document_id" => %{
          "type" => "string",
          "description" => "Document id returned by `create_document_upload`."
        }
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "document_id" => %{"type" => "string"},
        "status" => %{"type" => "string"},
        "byte_size" => %{"type" => "integer"},
        "checksum_sha256" => %{"type" => "string"},
        "url" => %{"type" => "string"}
      },
      "required" => ["document_id", "status", "byte_size", "checksum_sha256", "url"],
      "additionalProperties" => false
    }

  alias Atlas.Documents
  alias Atlas.Documents.Document
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description,
    do:
      "Finalize a previously reserved document upload. Verifies the bytes are in storage, records their size and sha256 checksum, and enqueues text extraction. Returns immediately after enqueuing; poll `get_document` for the eventual `ready` status."

  def execute(conn, %{"document_id" => document_id}) do
    with :ok <- Tool.authorize_scope(conn, "documents:write", "Document tools") do
      case Documents.finalize_pending_upload(document_id, audit_actor: Tool.current_user(conn)) do
        {:ok, %Document{} = document} ->
          {:ok,
           %{
             document_id: document.id,
             status: document.status,
             byte_size: document.byte_size,
             checksum_sha256: document.checksum_sha256,
             url: Tool.document_url(document)
           }}

        {:error, :document_not_found} ->
          {:error, "Document not found."}

        {:error, {:unexpected_status, status}} ->
          {:error, "Document is in #{status} state; only pending_upload documents can be finalized."}

        {:error, :not_found} ->
          {:error, "The upload has not landed in storage yet. PUT the bytes to the presigned URL first."}

        {:error, :already_finalized} ->
          {:error, "Document was already finalized by another caller."}

        {:error, {:upload_too_large, size, max}} ->
          {:error, "Upload is #{size} bytes; the document cap is #{max} bytes. The object has been discarded."}

        {:error, reason} ->
          {:error, inspect(reason)}
      end
    end
  end

  def execute(_conn, _args), do: {:error, "document_id is required."}
end
