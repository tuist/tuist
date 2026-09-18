defmodule Atlas.MCP.Tools.FinalizeLetterDocumentUpload do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "finalize_letter_document_upload",
    schema: %{
      "type" => "object",
      "required" => ["letter_id", "document_id"],
      "properties" => %{
        "letter_id" => %{"type" => "string"},
        "document_id" => %{
          "type" => "string",
          "description" => "Document id returned by `create_letter_document_upload`."
        }
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"letter" => Atlas.MCP.Serializers.Letters.letter_schema()},
      "required" => ["letter"],
      "additionalProperties" => false
    }

  alias Atlas.Letters
  alias Atlas.MCP.Serializers.Letters, as: LetterSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description,
    do:
      "Attach a previously uploaded outgoing PDF to its letter, move it to `collecting_delivery_details`, and queue delivery-detail preparation. Requires that the PDF bytes have been PUT to the URL returned by `create_letter_document_upload`. Does not send the letter."

  def execute(conn, %{"letter_id" => letter_id, "document_id" => document_id}) do
    with :ok <- Tool.authorize_executive(conn, "Letter tools") do
      case Letters.finalize_letter_document_upload(letter_id, document_id, Tool.current_user(conn)) do
        {:ok, letter} -> {:ok, %{letter: LetterSerializer.letter(letter)}}
        {:error, reason} -> {:error, format_error(reason)}
      end
    end
  end

  def execute(_conn, _args), do: {:error, "letter_id and document_id are required."}

  defp format_error(:not_found), do: "Letter not found."
  defp format_error(:letter_not_waiting_for_document), do: "This letter is not waiting for an outgoing document."
  defp format_error(:letter_document_not_found), do: "The reserved letter document could not be found."

  defp format_error(:letter_document_letter_mismatch),
    do: "The document does not belong to this letter's upload reservation."

  defp format_error({:letter_document_unexpected_status, status}),
    do: "The letter document is in #{status} state; only pending_upload documents can be finalized."

  defp format_error(:document_not_found), do: "The reserved letter document could not be found."

  defp format_error({:unexpected_status, status}),
    do: "The letter document is in #{status} state; only pending_upload documents can be finalized."

  defp format_error(:already_finalized), do: "The letter document was already finalized by another caller."

  defp format_error({:upload_too_large, size, max}),
    do: "The letter PDF is #{size} bytes; the document cap is #{max} bytes. The upload has been discarded."

  defp format_error(:letter_document_must_be_a_pdf),
    do: "The uploaded bytes are not a Portable Document Format file. PUT a valid PDF and try again."

  defp format_error(:unauthorized), do: "Letter tools are only available to executives."
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
