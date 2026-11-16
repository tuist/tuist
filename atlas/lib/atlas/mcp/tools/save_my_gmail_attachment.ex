defmodule Atlas.MCP.Tools.SaveMyGmailAttachment do
  @moduledoc """
  Copies one attachment from the caller's own Gmail mailbox into the document
  library, for example a receipt that then goes to a finance transaction with
  `finance_add_transaction_attachment`. The saved document is visible to
  everyone with document access, so it needs both the caller's Gmail consent
  and the `documents:write` scope.
  """

  use Atlas.MCP.Tool,
    name: "save_my_gmail_attachment",
    schema: %{
      "type" => "object",
      "required" => ["message_id", "part_id"],
      "properties" => %{
        "message_id" => %{"type" => "string", "description" => "Message id returned by search_my_gmail."},
        "part_id" => %{
          "type" => "string",
          "description" => "The attachment's part_id as listed by get_my_gmail_message."
        },
        "title" => %{
          "type" => "string",
          "description" => "Optional document title. Defaults to a title derived from the filename."
        }
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "required" => ["document_id", "title", "filename", "content_type", "byte_size"],
      "properties" => %{
        "document_id" => %{"type" => "string"},
        "title" => %{"type" => "string"},
        "filename" => %{"type" => "string"},
        "content_type" => %{"type" => "string"},
        "byte_size" => %{"type" => "integer"}
      },
      "additionalProperties" => false
    }

  alias Atlas.Connections.Gmail
  alias Atlas.Documents
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.ManageAccountConnections

  @impl EMCP.Tool
  def description do
    "Save one attachment from the caller's own Gmail mailbox to the Atlas document library and return its document_id, " <>
      "for example to attach a receipt with finance_add_transaction_attachment. Find the part_id with get_my_gmail_message. " <>
      "The saved document is visible to everyone with document access."
  end

  def execute(conn, %{"message_id" => message_id, "part_id" => part_id} = args)
      when is_binary(message_id) and is_binary(part_id) do
    with true <- ManageAccountConnections.allowed_context?(conn) || {:error, :shared_identity},
         :ok <- Tool.authorize_scope(conn, "documents:write", "Saving Gmail attachments"),
         user = Tool.current_user(conn),
         {:ok, attachment} <- Gmail.get_attachment(user, message_id, part_id),
         {:ok, document} <- save(attachment, user, args) do
      {:ok,
       %{
         document_id: document.id,
         title: document.title,
         filename: document.original_filename,
         content_type: document.content_type,
         byte_size: document.byte_size
       }}
    else
      {:error, :shared_identity} -> {:error, "Personal Gmail is unavailable to shared Slack identities."}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, Tool.format_changeset_errors(changeset)}
      {:error, message} when is_binary(message) -> {:error, message}
      {:error, reason} -> {:error, ManageAccountConnections.connection_error("Gmail", reason)}
    end
  end

  def execute(_conn, _args), do: {:error, "message_id and part_id are required."}

  defp save(attachment, user, args) do
    case Documents.create_from_binary(attachment.body, attrs(attachment, user, args), audit_actor: user) do
      {:ok, document} -> {:ok, document}
      {:error, %Ecto.Changeset{}} = error -> error
      {:error, _reason} -> {:error, "Could not save the attachment to the document library. Try again shortly."}
    end
  end

  defp attrs(attachment, user, args) do
    attrs = %{
      "original_filename" => attachment.filename,
      "content_type" => attachment.mime_type || "application/octet-stream",
      "source" => "email",
      "uploaded_by_id" => user.id
    }

    case args["title"] do
      title when is_binary(title) and title != "" -> Map.put(attrs, "title", title)
      _no_title -> attrs
    end
  end
end
