defmodule Atlas.MCP.Tools.ListEmailOutboxTest do
  use Atlas.MCP.ToolCase

  import Atlas.MailboxFixtures

  alias Atlas.MCP.Tools.ListEmailOutbox

  test "lists deliveries and support replies" do
    delivery = insert_delivery!(%{recipient_email: "billing@acme.example"})
    thread = insert_support_thread!(%{subject: "Cache misses on CI"})
    reply = insert_support_reply!(thread)

    assert {:ok, %{emails: emails, count: 2, total_count: 2}} =
             execute_tool(ListEmailOutbox, executive_mcp_conn(), %{})

    assert %{kind: "direct", to_emails: ["billing@acme.example"], status: "sent"} =
             Enum.find(emails, &(&1.id == delivery.id))

    assert %{kind: "support_reply", subject: "Re: Cache misses on CI", support_thread_id: thread_id} =
             Enum.find(emails, &(&1.id == reply.id))

    assert thread_id == thread.id
  end

  test "filters by kind and status" do
    insert_delivery!()
    failed = insert_delivery!(%{kind: "welcome", status: "failed", delivered_at: nil})
    insert_support_reply!(insert_support_thread!())

    conn = executive_mcp_conn()

    assert {:ok, %{emails: [%{kind: "support_reply"}]}} =
             execute_tool(ListEmailOutbox, conn, %{"kind" => "support_reply"})

    assert {:ok, %{emails: [%{id: id}]}} = execute_tool(ListEmailOutbox, conn, %{"status" => "failed"})
    assert id == failed.id
  end

  test "requires the support read scope" do
    conn = mcp_conn(insert_user!(%{scopes: ["gtm:read"]}))

    assert {:error, "Email outbox tools require the support:read scope."} =
             execute_tool(ListEmailOutbox, conn, %{})
  end
end
