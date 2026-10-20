defmodule Atlas.MCP.Tools.UploadPostalLetter do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "upload_postal_letter",
    schema: %{
      "type" => "object",
      "required" => ["filename", "pdf_base64"],
      "properties" => %{
        "account_id" => %{
          "type" => "string",
          "description" =>
            "Optional account identifier. When omitted, Atlas matches the letter to an account automatically."
        },
        "filename" => %{"type" => "string"},
        "pdf_base64" => %{
          "type" => "string",
          "description" => "Encoded Portable Document Format letter to send."
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
  def description do
    "Upload an outbound letter and queue agent-led account matching and delivery-address preparation. This does not send the letter."
  end

  def execute(conn, args) do
    with :ok <- Tool.authorize_scope(conn, "letters:write", "Letter tools"),
         {:ok, body} <- decode_pdf(args["pdf_base64"]) do
      upload = %{body: body, filename: args["filename"]}

      result =
        case args["account_id"] do
          account_id when is_binary(account_id) and account_id != "" ->
            Letters.upload_letter(account_id, upload, Tool.current_user(conn))

          _account_id ->
            Letters.upload_letter(upload, Tool.current_user(conn))
        end

      case result do
        {:ok, letter} -> {:ok, %{letter: LetterSerializer.letter(letter)}}
        {:error, reason} -> {:error, format_error(reason)}
      end
    end
  end

  defp decode_pdf(value) when is_binary(value) do
    case Base.decode64(value) do
      {:ok, body} when byte_size(body) <= 50_000_000 -> {:ok, body}
      {:ok, _body} -> {:error, "The letter is too large."}
      :error -> {:error, "The letter is not valid encoded data."}
    end
  end

  defp decode_pdf(_value), do: {:error, "The letter is missing."}

  defp format_error(:account_not_found), do: "Company not found."
  defp format_error(:letter_document_must_be_a_pdf), do: "Upload a Portable Document Format letter."

  defp format_error({:sender_details_missing, _fields}),
    do: "Complete the company sender details before uploading a letter."

  defp format_error(:unauthorized), do: "Letter tools are only available to executives."
  defp format_error(reason), do: inspect(reason)
end
