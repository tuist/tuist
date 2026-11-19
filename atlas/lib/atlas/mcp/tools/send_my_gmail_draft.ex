defmodule Atlas.MCP.Tools.SendMyGmailDraft do
  @moduledoc """
  Sends a draft immediately from the caller's own mailbox. The calling client
  handles user confirmation; Atlas does not create a separate approval.
  """

  use Atlas.MCP.Tool,
    name: "send_my_gmail_draft",
    schema: %{
      "type" => "object",
      "required" => ["draft_id"],
      "properties" => %{
        "draft_id" => %{"type" => "string", "description" => "Draft id returned by create_my_gmail_draft."}
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "required" => ["draft_id", "message_id", "thread_id"],
      "properties" => %{
        "draft_id" => %{"type" => "string"},
        "message_id" => %{"type" => ["string", "null"]},
        "thread_id" => %{"type" => ["string", "null"]}
      },
      "additionalProperties" => false
    }

  alias Atlas.Connections.Gmail
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.GmailSerializers
  alias Atlas.MCP.Tools.ManageAccountConnections
  alias Atlas.Users.User

  @impl EMCP.Tool
  def description do
    "Send the current draft immediately from the caller's own Gmail mailbox, including its recipients, body and " <>
      "attachments. The calling client must obtain user confirmation before calling; Atlas has no separate approval step. " <>
      "Requires Allow Gmail drafts in Atlas settings and a personal Atlas MCP session. " <>
      "If the send is unconfirmed, check Sent with search_my_gmail before retrying to avoid duplicate mail."
  end

  def execute(conn, args) do
    with true <- ManageAccountConnections.allowed_context?(conn) || {:error, :shared_identity},
         :ok <- Tool.authorize_authenticated(conn, "Gmail tools"),
         :ok <- GmailSerializers.validate(__MODULE__, args),
         %User{} = user <- mcp_user(conn),
         {:ok, sent} <- Gmail.send_draft(user, args["draft_id"]) do
      {:ok, sent}
    else
      {:error, :send_unconfirmed} -> {:error, unconfirmed_message()}
      error -> GmailSerializers.error(error)
    end
  end

  # Sending remains limited to a person's own Atlas MCP session.
  defp mcp_user(%{assigns: %{current_user: %User{} = user, audit_interface: "mcp"}}), do: user

  defp mcp_user(_conn), do: {:error, "Sending Gmail drafts is only callable over a personal Atlas MCP session."}

  defp unconfirmed_message do
    "Gmail did not confirm the send. Check the Sent folder with search_my_gmail " <>
      "(in:sent) before retrying; the message may already have been sent."
  end
end
