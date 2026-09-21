defmodule Atlas.MCP.Tools.SupportToolsTest do
  use Atlas.MCP.ToolCase
  use Oban.Testing, repo: Atlas.Repo

  alias Atlas.Inbox
  alias Atlas.Inbox.EmailParser
  alias Atlas.MCP.Tools.AddSupportThreadNote
  alias Atlas.MCP.Tools.GetSupportThread
  alias Atlas.MCP.Tools.ListSupportThreads
  alias Atlas.MCP.Tools.ReplyToSupportThread
  alias Atlas.MCP.Tools.UpdateSupportThread
  alias Atlas.Support
  alias Atlas.Support.Workers.DeliverReply

  test "lists and retrieves a customer support conversation" do
    thread = support_thread!()
    conn = executive_mcp_conn()

    assert {:ok, %{threads: [listed_thread], count: 1}} = execute_tool(ListSupportThreads, conn, %{})
    assert listed_thread.id == thread.id

    assert {:ok, fetched_thread} = execute_tool(GetSupportThread, conn, %{"thread_id" => thread.id})
    assert fetched_thread.id == thread.id
    assert [%{kind: "inbound"}] = fetched_thread.messages
  end

  test "queues a reply and updates assignment and lifecycle" do
    thread = support_thread!()
    owner = insert_user!(%{role: :executive})
    conn = mcp_conn(owner)

    assert {:ok, %{thread: replied_thread, message: message}} =
             execute_tool(ReplyToSupportThread, conn, %{
               "thread_id" => thread.id,
               "body" => "We are investigating.",
               "attachments" => [
                 %{
                   "filename" => "investigation.txt",
                   "content_base64" => "#{Base.encode64("We are investigating.")}\n"
                 }
               ]
             })

    assert replied_thread.status == "waiting"
    assert message.kind == "outbound"
    assert [%{filename: "investigation.txt", content_type: "text/plain", byte_size: 21}] = message.attachments
    assert_enqueued(worker: DeliverReply, args: %{"message_id" => message.id})

    assert {:ok, %{message: note}} =
             execute_tool(AddSupportThreadNote, conn, %{"thread_id" => thread.id, "body" => "Track this after launch."})

    assert note.kind == "note"
    assert note.author.id == owner.id

    assert {:ok, updated_thread} =
             execute_tool(UpdateSupportThread, conn, %{
               "thread_id" => thread.id,
               "owner_id" => owner.id,
               "status" => "resolved"
             })

    assert updated_thread.owner.id == owner.id
    assert updated_thread.status == "resolved"
  end

  test "does not expose customer support conversations to non-executive agents" do
    thread = support_thread!()
    employee = insert_user!(%{role: :employee})

    assert {:error, "Support tools require the support:read scope."} =
             execute_tool(ListSupportThreads, mcp_conn(employee), %{})

    assert {:error, "Support tools require the support:read scope."} =
             execute_tool(GetSupportThread, mcp_conn(employee), %{"thread_id" => thread.id})
  end

  defp support_thread! do
    suffix = System.unique_integer([:positive])

    raw_email = """
    Message-ID: <mcp-support-#{suffix}@example.com>
    From: Customer <mcp-support-#{suffix}@example.com>
    To: contact@tuist.dev
    Subject: Support through an agent

    Please help.
    """

    {:ok, inbox_email} =
      Inbox.persist_inbound(raw_email,
        envelope: %{"from" => "mcp-support-#{suffix}@example.com", "to" => "contact@tuist.dev"}
      )

    {:ok, %{thread: thread}} = Support.ingest_inbound(EmailParser.parse(raw_email), inbox_email.id)
    thread
  end
end
