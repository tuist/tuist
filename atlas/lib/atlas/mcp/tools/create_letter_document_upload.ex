defmodule Atlas.MCP.Tools.CreateLetterDocumentUpload do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "create_letter_document_upload",
    schema: %{
      "type" => "object",
      "required" => ["letter_id", "filename"],
      "properties" => %{
        "letter_id" => %{"type" => "string"},
        "filename" => %{
          "type" => "string",
          "description" => "Filename as it should appear in the document library, including its .pdf extension."
        },
        "expires_in" => %{
          "type" => "integer",
          "minimum" => 60,
          "maximum" => 21_600,
          "description" => "Presigned URL lifetime in seconds. Defaults to 3600 (1 hour)."
        }
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "letter" => Atlas.MCP.Serializers.Letters.letter_schema(),
        "document_id" => %{"type" => "string"},
        "upload_url" => %{"type" => "string"},
        "upload_method" => %{"type" => "string"},
        "upload_expires_at" => %{"type" => "string"},
        "required_headers" => %{
          "type" => "object",
          "additionalProperties" => %{"type" => "string"}
        }
      },
      "required" => ["letter", "document_id", "upload_url", "upload_method", "upload_expires_at", "required_headers"],
      "additionalProperties" => false
    }

  alias Atlas.Letters
  alias Atlas.MCP.Serializers.Letters, as: LetterSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description,
    do:
      "Reserve a pending outgoing document for a letter that is waiting for one and return a short-lived presigned PUT URL. Upload the PDF bytes to that URL with the `Content-Type` header from `required_headers`, then call `finalize_letter_document_upload` with the returned `document_id`. Does not send the letter."

  def execute(conn, %{"letter_id" => letter_id, "filename" => filename} = args) do
    with :ok <- Tool.authorize_scope(conn, "letters:write", "Letter tools") do
      case Letters.create_letter_document_upload(
             letter_id,
             %{filename: filename},
             Tool.current_user(conn),
             build_opts(args)
           ) do
        {:ok, %{letter: letter, document: document} = reservation} ->
          {:ok,
           %{
             letter: LetterSerializer.letter(letter),
             document_id: document.id,
             upload_url: reservation.upload_url,
             upload_method: "PUT",
             upload_expires_at: Tool.iso8601(reservation.upload_expires_at),
             required_headers: reservation.required_headers
           }}

        {:error, reason} ->
          {:error, format_error(reason)}
      end
    end
  end

  def execute(_conn, _args), do: {:error, "letter_id and filename are required."}

  defp build_opts(args) do
    case args["expires_in"] do
      value when is_integer(value) and value > 0 -> [expires_in: value]
      _ -> []
    end
  end

  defp format_error(:not_found), do: "Letter not found."
  defp format_error(:letter_not_waiting_for_document), do: "This letter is not waiting for an outgoing document."
  defp format_error(:letter_document_filename_missing), do: "Provide a non-empty PDF filename."
  defp format_error(:original_filename_required), do: "Provide a non-empty PDF filename."
  defp format_error(:content_type_required), do: "The letter document upload requires a content type."
  defp format_error(:unauthorized), do: "Letter tools are only available to executives."
  defp format_error(%Ecto.Changeset{} = changeset), do: Tool.format_changeset_errors(changeset)
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
