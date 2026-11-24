defmodule Atlas.MCP.Tools.UpdateMyGmailDraft do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "update_my_gmail_draft",
    schema: %{
      "type" => "object",
      "required" => ["draft_id", "to", "subject", "body"],
      "properties" =>
        Map.merge(Atlas.MCP.Tools.GmailSerializers.draft_input_properties(), %{
          "draft_id" => %{"type" => "string", "description" => "Draft id returned by create_my_gmail_draft."},
          "keep_attachments" => %{
            "type" => "boolean",
            "default" => true,
            "description" =>
              "Keep the draft's current attachments and add attachments to them. False replaces them with attachments, or removes them when attachments is omitted."
          }
        }),
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "required" => ["draft"],
      "properties" => %{"draft" => Atlas.MCP.Tools.GmailSerializers.draft_schema()},
      "additionalProperties" => false
    }

  alias Atlas.Connections.Gmail
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.GmailSerializers
  alias Atlas.MCP.Tools.ManageAccountConnections

  @impl EMCP.Tool
  def description do
    "Replace the recipients, subject and body of a draft in the caller's own Gmail mailbox. Set body_format to markdown or html for rich text; default plain. Without " <>
      "reply_to_message_id the draft keeps its thread and reply headers. The draft keeps its attachments, and attachments adds files; " <>
      "set keep_attachments to false to replace or remove them. Nothing is sent. " <>
      "Requires Allow Gmail drafts in Atlas settings."
  end

  def execute(conn, args) do
    with true <- ManageAccountConnections.allowed_context?(conn) || {:error, :shared_identity},
         :ok <- Tool.authorize_authenticated(conn, "Gmail tools"),
         :ok <- GmailSerializers.validate(__MODULE__, args),
         {:ok, draft} <- Gmail.update_draft(Tool.current_user(conn), args["draft_id"], args) do
      {:ok, %{draft: GmailSerializers.draft(draft)}}
    else
      error -> GmailSerializers.error(error)
    end
  end
end
