defmodule Atlas.MCP.Tools.CreateDocumentUpload do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "create_document_upload",
    schema: %{
      "type" => "object",
      "required" => ["original_filename", "content_type"],
      "properties" => %{
        "original_filename" => %{
          "type" => "string",
          "description" => "Filename as it should appear in the library, including its extension."
        },
        "content_type" => %{
          "type" => "string",
          "description" =>
            "MIME type of the file being uploaded. Must be sent verbatim as the `Content-Type` header when PUTting the bytes."
        },
        "title" => %{
          "type" => "string",
          "description" => "Optional human title. Defaults to a title derived from the filename."
        },
        "account_id" => %{
          "type" => "string",
          "description" => "Optional Atlas account id to pre-associate with the document."
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
        "document_id" => %{"type" => "string"},
        "upload_url" => %{"type" => "string"},
        "upload_method" => %{"type" => "string"},
        "upload_expires_at" => %{"type" => "string"},
        "required_headers" => %{
          "type" => "object",
          "additionalProperties" => %{"type" => "string"}
        }
      },
      "required" => ["document_id", "upload_url", "upload_method", "upload_expires_at", "required_headers"],
      "additionalProperties" => false
    }

  alias Atlas.Documents
  alias Atlas.MCP.Tool
  alias Atlas.Users.User

  @impl EMCP.Tool
  def description,
    do:
      "Reserve a document row and return a short-lived presigned URL. Upload the bytes with an HTTP PUT to that URL, sending the `Content-Type` header returned in `required_headers` verbatim, then call `finalize_document_upload` with the returned `document_id` to promote the row and enqueue processing."

  def execute(conn, %{"original_filename" => filename, "content_type" => content_type} = args) do
    with :ok <- Tool.authorize_scope(conn, "documents:write", "Document tools"),
         %User{} = user <- Tool.current_user(conn) do
      attrs =
        %{
          "original_filename" => filename,
          "content_type" => content_type,
          "uploaded_by_id" => user.id
        }
        |> maybe_put("title", args["title"])
        |> maybe_put("account_id", args["account_id"])

      opts = [audit_actor: user]

      opts =
        case args["expires_in"] do
          value when is_integer(value) and value > 0 -> Keyword.put(opts, :expires_in, value)
          _no_override -> opts
        end

      case Documents.create_pending_upload(attrs, opts) do
        {:ok, %{document: document} = reservation} ->
          {:ok,
           %{
             document_id: document.id,
             upload_url: reservation.upload_url,
             upload_method: "PUT",
             upload_expires_at: Tool.iso8601(reservation.upload_expires_at),
             required_headers: reservation.required_headers
           }}

        {:error, :content_type_required} ->
          {:error, "content_type is required."}

        {:error, :original_filename_required} ->
          {:error, "original_filename is required."}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:error, Tool.format_changeset_errors(changeset)}

        {:error, reason} ->
          {:error, inspect(reason)}
      end
    end
  end

  def execute(_conn, _args), do: {:error, "original_filename and content_type are required."}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
