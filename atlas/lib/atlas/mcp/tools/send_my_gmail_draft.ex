defmodule Atlas.MCP.Tools.SendMyGmailDraft do
  @moduledoc """
  Sends a draft from the caller's own mailbox after its owner approved that
  exact content in Atlas. The approval pins a digest of the recipients,
  subject, body and attachments, is spent by one send and expires after an
  hour; a draft that changed since then needs a new approval.
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
    "Send a draft from the caller's own Gmail mailbox. Every send needs the mailbox owner's approval of the draft's " <>
      "current recipients, subject and body: the first call files a request and returns a link, the person reviews " <>
      "and approves it in Atlas, and the same call then sends the draft once. The person may edit the draft before " <>
      "approving, so read the sent message with get_my_gmail_message if you need its final text. Editing the draft " <>
      "after approval voids it. Requires Allow Gmail drafts in Atlas settings."
  end

  def execute(conn, args) do
    with true <- ManageAccountConnections.allowed_context?(conn) || {:error, :shared_identity},
         :ok <- Tool.authorize_authenticated(conn, "Gmail tools"),
         :ok <- GmailSerializers.validate(__MODULE__, args),
         %User{} = user <- mcp_user(conn),
         {:ok, sent} <- Gmail.send_draft(user, args["draft_id"]) do
      {:ok, sent}
    else
      {:error, {:approval_required, approval, changed?}} -> {:error, approval_message(approval, changed?)}
      {:error, :send_unconfirmed} -> {:error, unconfirmed_message()}
      error -> GmailSerializers.error(error)
    end
  end

  # Approval-gated tools run only over a person's own Atlas MCP session.
  defp mcp_user(%{assigns: %{current_user: %User{} = user, audit_interface: "mcp"}}), do: user

  defp mcp_user(_conn),
    do: {:error, "Sending Gmail drafts needs the mailbox owner's approval and is only callable over Atlas MCP."}

  defp approval_message(approval, changed?) do
    prefix =
      if changed?,
        do: "The draft changed after it was approved, so that approval no longer covers it. ",
        else: ""

    prefix <>
      "Sending this draft needs the mailbox owner's approval of its current content. Ask the person you are " <>
      "working for to review request #{approval.id} at " <>
      "#{AtlasWeb.Endpoint.url()}/settings/connections#gmail-approval-#{approval.id} " <>
      "(it expires at #{DateTime.to_iso8601(approval.expires_at)}), then repeat the call without editing the draft. " <>
      "Never approve it yourself."
  end

  defp unconfirmed_message do
    "Gmail did not confirm the send and the approval is spent. Check the Sent folder with search_my_gmail " <>
      "(in:sent) before asking for a new approval; do not retry blindly."
  end
end
