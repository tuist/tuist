defmodule Atlas.MCP.Tools.FinanceAddTransactionAttachment do
  @moduledoc """
  Adds an attachment from the Atlas document library to a finance transaction.

  This is the primary tool for the "missing attachment" workflow: when an
  executive identifies a transaction that lacks a receipt or supporting
  document that exists in Atlas's document library, this tool downloads the
  document from S3 and uploads it to the finance provider.
  """

  use Atlas.MCP.Tool,
    name: "finance_add_transaction_attachment",
    schema: %{
      "type" => "object",
      "properties" => %{
        "source_key" => %{
          "type" => "string",
          "description" => "The finance source key."
        },
        "transaction_external_id" => %{
          "type" => "string",
          "description" =>
            "The provider transaction external ID to attach the document to. Obtain from finance_get_transaction."
        },
        "document_id" => %{
          "type" => "string",
          "description" => "The Atlas document ID to upload as an attachment."
        }
      },
      "required" => ["source_key", "transaction_external_id", "document_id"]
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "success" => %{"type" => "boolean"},
        "attachment_id" => %{"type" => ["string", "null"]},
        "document_id" => %{"type" => "string"},
        "transaction_external_id" => %{"type" => "string"},
        "filename" => %{"type" => ["string", "null"]},
        "message" => %{"type" => ["string", "null"]}
      },
      "required" => ["success", "attachment_id", "document_id", "transaction_external_id", "filename", "message"],
      "additionalProperties" => false
    }

  alias Atlas.Audit
  alias Atlas.Documents
  alias Atlas.Documents.Document
  alias Atlas.Documents.Storage
  alias Atlas.Finance.Config
  alias Atlas.Finance.Providers.Qonto
  alias Atlas.MCP.Tool

  def description do
    "Upload a document from the Atlas document library as an attachment to a finance transaction. Use this when a transaction is missing a receipt or supporting document that already exists in Atlas."
  end

  def execute(conn, %{
        "source_key" => source_key,
        "transaction_external_id" => transaction_external_id,
        "document_id" => document_id
      }) do
    with :ok <- Tool.authorize_scope(conn, "finance:write", "Finance tools"),
         {:ok, source} <- Config.fetch_source(source_key),
         %Document{} = document <- Documents.get_document(document_id),
         {:ok, document_content} <- download_document_content(document) do
      filename = document.original_filename || "document-#{document_id}"
      content_type = document.content_type || "application/octet-stream"

      case Qonto.add_attachment(source, transaction_external_id, document_content, filename, content_type) do
        {:ok, created_attachment} ->
          Audit.record("finance_transaction_attachment.added", %{
            target_type: "finance_transaction",
            target_id: transaction_external_id,
            target_label: filename,
            metadata: %{
              "source_key" => source_key,
              "document_id" => document_id,
              "attachment_id" => created_attachment["id"]
            }
          })

          {:ok,
           %{
             success: true,
             attachment_id: created_attachment["id"],
             document_id: document_id,
             transaction_external_id: transaction_external_id,
             filename: filename,
             message: "Attachment uploaded successfully."
           }}

        {:error, reason} ->
          {:error, "Failed to upload attachment: #{inspect(reason)}"}
      end
    else
      {:error, :source_not_configured} ->
        {:error, "No finance source configured with key '#{source_key}'."}

      nil ->
        {:error, "Document not found with id '#{document_id}'."}

      {:error, reason} ->
        {:error, "Failed to add attachment: #{inspect(reason)}"}
    end
  end

  def execute(_conn, _args) do
    {:error, "source_key, transaction_external_id, and document_id are required."}
  end

  defp download_document_content(%Document{storage_key: storage_key, original_filename: filename})
       when is_binary(storage_key) and storage_key != "" do
    case Storage.get_object(storage_key) do
      {:ok, %{body: body}} when is_binary(body) and byte_size(body) > 0 ->
        {:ok, body}

      {:ok, _result} ->
        {:error, "Document '#{filename}' has no content in storage."}

      {:error, reason} ->
        {:error, "Failed to read document from storage: #{inspect(reason)}"}
    end
  end

  defp download_document_content(%Document{original_filename: filename}) do
    {:error, "Document '#{filename}' has no storage key."}
  end
end
