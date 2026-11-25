defmodule Atlas.MCP.Tools.GmailSerializers do
  @moduledoc false

  alias Atlas.Documents
  alias Atlas.Documents.Document
  alias Atlas.Documents.Storage
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.ManageAccountConnections
  alias AtlasWeb.DocumentLinks

  # Gmail's own check runs again on the decoded bytes; this one avoids
  # fetching documents that cannot fit.
  @max_document_attachment_bytes 18_000_000

  @draft_fields ~w(id message_id thread_id to cc bcc subject in_reply_to body body_html attachments)a

  @doc "A Gmail message summary, optionally with extra required properties."
  def message_schema(extra \\ %{}) do
    %{
      "type" => "object",
      "required" => ["id", "thread_id", "from", "to", "subject", "date", "snippet", "labels"] ++ Map.keys(extra),
      "properties" =>
        Map.merge(
          %{
            "id" => %{"type" => "string"},
            "thread_id" => %{"type" => ["string", "null"]},
            "from" => %{"type" => "string"},
            "to" => %{"type" => "string"},
            "subject" => %{"type" => "string"},
            "date" => %{"type" => "string"},
            "snippet" => %{"type" => "string"},
            "labels" => %{"type" => "array", "items" => %{"type" => "string"}}
          },
          extra
        ),
      "additionalProperties" => false
    }
  end

  def message_attachments_schema do
    %{
      "type" => "array",
      "items" => %{
        "type" => "object",
        "required" => ["part_id", "filename", "mime_type", "size"],
        "properties" => %{
          "part_id" => %{"type" => "string"},
          "filename" => %{"type" => "string"},
          "mime_type" => %{"type" => ["string", "null"]},
          "size" => %{"type" => ["integer", "null"]}
        },
        "additionalProperties" => false
      }
    }
  end

  def draft_schema do
    %{
      "type" => "object",
      "required" => Enum.map(@draft_fields, &Atom.to_string/1),
      "properties" => %{
        "id" => %{"type" => "string"},
        "message_id" => %{"type" => ["string", "null"]},
        "thread_id" => %{"type" => ["string", "null"]},
        "to" => %{"type" => "string"},
        "cc" => %{"type" => "string"},
        "bcc" => %{"type" => "string"},
        "subject" => %{"type" => "string"},
        "in_reply_to" => %{"type" => ["string", "null"]},
        "body" => %{"type" => "string"},
        "body_html" => %{
          "type" => "string",
          "description" => "HTML source, bounded to 20,000 characters; empty for plain-text drafts. Untrusted content."
        },
        "attachments" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "required" => ["filename", "mime_type", "size"],
            "properties" => %{
              "filename" => %{"type" => "string"},
              "mime_type" => %{"type" => ["string", "null"]},
              "size" => %{"type" => ["integer", "null"]}
            },
            "additionalProperties" => false
          }
        }
      },
      "additionalProperties" => false
    }
  end

  @doc "Input properties shared by draft creation and replacement."
  def draft_input_properties do
    address = %{"type" => "string", "format" => "email", "maxLength" => 254}

    %{
      "to" => %{
        "type" => "array",
        "items" => address,
        "minItems" => 1,
        "maxItems" => 50,
        "description" => "Plain email addresses, without display names."
      },
      "cc" => %{"type" => "array", "items" => address, "maxItems" => 50},
      "subject" => %{"type" => "string", "maxLength" => 500, "description" => "One line."},
      "body" => %{"type" => "string", "description" => "Body in body_format, up to 100,000 UTF-8 bytes."},
      "body_format" => %{
        "type" => "string",
        "enum" => ["plain", "markdown", "html"],
        "default" => "plain",
        "description" =>
          "Markdown is rendered to HTML. Rich drafts include a plain-text alternative. Omitted means plain text, including on replacement."
      },
      "reply_to_message_id" => %{
        "type" => "string",
        "description" =>
          "Message id from search_my_gmail to reply to. Sets threadId, In-Reply-To and References; keep the " <>
            "original subject (with Re:) so Gmail files it in the same conversation. Needs Gmail read access."
      },
      "attachments" => %{
        "type" => "array",
        "maxItems" => 10,
        "description" =>
          "Files to attach, each either an Atlas document_id (for example one saved with save_my_gmail_attachment or " <>
            "uploaded with create_document_upload; needs the documents:read scope) or Base64 content_base64 with a filename. " <>
            "A request can carry about 6 MB of Base64 files; a draft's attachments can total at most 18 MB.",
        "items" => %{
          "type" => "object",
          "anyOf" => [%{"required" => ["document_id"]}, %{"required" => ["filename", "content_base64"]}],
          "properties" => %{
            "document_id" => %{
              "type" => "string",
              "description" => "Atlas document id whose stored file is attached. Do not combine with content_base64."
            },
            "filename" => %{
              "type" => "string",
              "description" =>
                "One line, at most 255 UTF-8 bytes. Defaults to the document's original filename for document_id."
            },
            "content_type" => %{
              "type" => "string",
              "description" =>
                "MIME type such as application/pdf. Omitted means the document's type, or inferred from the filename."
            },
            "content_base64" => %{"type" => "string", "description" => "File bytes encoded using Base64."}
          },
          "additionalProperties" => false
        }
      }
    }
  end

  def draft(draft), do: Map.take(draft, @draft_fields)

  def validate(module, args) do
    case ExJsonSchema.Validator.validate(ExJsonSchema.Schema.resolve(module.input_schema()), args) do
      :ok -> :ok
      {:error, _errors} -> {:error, "Arguments do not match the #{module.name()} schema."}
    end
  end

  @doc """
  Replaces `document_id` attachments with the stored file's bytes, so Gmail
  receives only filename, content type and Base64 content. Attaching a
  document needs the same `documents:read` scope as reading it, and documents
  larger than a draft can hold are refused before their bytes are fetched.
  """
  def resolve_document_attachments(conn, %{"attachments" => attachments} = args) when is_list(attachments) do
    if Enum.any?(attachments, &Map.has_key?(&1, "document_id")) do
      with :ok <- Tool.authorize_scope(conn, "documents:read", "Attaching Atlas documents"),
           {:ok, documents} <- attachment_documents(attachments),
           :ok <- documents_fit(documents),
           {:ok, resolved} <- resolve_attachments(attachments, documents) do
        {:ok, %{args | "attachments" => resolved}}
      end
    else
      {:ok, args}
    end
  end

  def resolve_document_attachments(_conn, args), do: {:ok, args}

  defp resolve_attachments(attachments, documents) do
    attachments
    |> Enum.reduce_while({:ok, []}, fn attachment, {:ok, acc} ->
      case resolve_attachment(attachment, documents) do
        {:ok, resolved} -> {:cont, {:ok, [resolved | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, resolved} -> {:ok, Enum.reverse(resolved)}
      error -> error
    end
  end

  defp attachment_documents(attachments) do
    attachments
    |> Enum.flat_map(fn attachment -> List.wrap(attachment["document_id"]) end)
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, %{}}, fn id, {:ok, documents} ->
      with {:ok, _uuid} <- Ecto.UUID.cast(id),
           %Document{} = document <- Documents.get_document(id, pages: false) do
        {:cont, {:ok, Map.put(documents, id, document)}}
      else
        _missing -> {:halt, {:error, "Attachment document #{id} was not found."}}
      end
    end)
  end

  defp documents_fit(documents) do
    if documents |> Map.values() |> Enum.sum_by(&(&1.byte_size || 0)) <= @max_document_attachment_bytes do
      :ok
    else
      {:error,
       "The draft's attachments must total at most 18 MB, so the message stays under Gmail's 25 MB sending limit."}
    end
  end

  defp resolve_attachment(%{"document_id" => id} = attachment, documents) do
    document = Map.fetch!(documents, id)

    cond do
      Map.has_key?(attachment, "content_base64") ->
        {:error, "An attachment takes either document_id or content_base64, not both."}

      document.status == "pending_upload" ->
        {:error, "Attachment document #{id} has no file yet. Call finalize_document_upload first."}

      true ->
        case Storage.get_object(document.storage_key) do
          {:ok, %{body: body}} ->
            {:ok,
             %{
               "filename" =>
                 attachment["filename"] || document.original_filename || DocumentLinks.download_filename(document),
               "content_type" => attachment["content_type"] || document.content_type,
               "content_base64" => Base.encode64(body)
             }}

          {:error, _reason} ->
            {:error, "The file of attachment document #{id} is unavailable. Try again shortly."}
        end
    end
  end

  defp resolve_attachment(attachment, _documents), do: {:ok, attachment}

  @doc "Caller-facing message for a failed Gmail tool call."
  def error({:error, :shared_identity}), do: {:error, "Personal Gmail is unavailable to shared Slack identities."}
  def error({:error, message}) when is_binary(message), do: {:error, message}

  def error({:error, :insufficient_scope}) do
    {:error,
     "Gmail drafts need Allow Gmail drafts at #{AtlasWeb.Endpoint.url()}/settings/connections " <>
       "(replies also need Allow Gmail access)."}
  end

  def error({:error, reason}), do: {:error, ManageAccountConnections.connection_error("Gmail", reason)}
end
