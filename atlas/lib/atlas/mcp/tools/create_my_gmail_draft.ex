defmodule Atlas.MCP.Tools.CreateMyGmailDraft do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "create_my_gmail_draft",
    schema: %{
      "type" => "object",
      "required" => ["to", "subject", "body"],
      "properties" => Atlas.MCP.Tools.GmailSerializers.draft_input_properties(),
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
    "Create a plain-text draft in the caller's own Gmail mailbox. Nothing is sent: the person reviews it in Gmail, " <>
      "or approves a send_my_gmail_draft request in Atlas. Pass reply_to_message_id to reply within a thread. " <>
      "Requires Allow Gmail drafts in Atlas settings."
  end

  def execute(conn, args) do
    with true <- ManageAccountConnections.allowed_context?(conn) || {:error, :shared_identity},
         :ok <- Tool.authorize_authenticated(conn, "Gmail tools"),
         :ok <- GmailSerializers.validate(__MODULE__, args),
         {:ok, draft} <- Gmail.create_draft(Tool.current_user(conn), args) do
      {:ok, %{draft: GmailSerializers.draft(draft)}}
    else
      error -> GmailSerializers.error(error)
    end
  end
end
