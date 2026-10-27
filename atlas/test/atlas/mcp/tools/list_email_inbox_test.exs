defmodule Atlas.MCP.Tools.ListEmailInboxTest do
  use Atlas.MCP.ToolCase

  import Atlas.MailboxFixtures

  alias Atlas.MCP.Tools.ListEmailInbox

  test "lists received emails with their support conversation" do
    thread = insert_support_thread!(%{customer_email: "ada@example.com", subject: "Cache misses on CI"})
    message = insert_inbound_message!(thread)

    assert {:ok, %{emails: [email], count: 1, total_count: 1}} =
             execute_tool(ListEmailInbox, executive_mcp_conn(), %{})

    assert email.id == message.id
    assert email.subject == "Cache misses on CI"
    assert email.from_email == "ada@example.com"
    assert email.support_thread_id == thread.id
    assert email.support_thread_status == "open"
  end

  test "searches by sender" do
    insert_inbound_message!(insert_support_thread!(%{customer_email: "ada@example.com"}))
    insert_inbound_message!(insert_support_thread!(%{customer_email: "grace@example.com"}))

    assert {:ok, %{emails: [%{from_email: "grace@example.com"}]}} =
             execute_tool(ListEmailInbox, executive_mcp_conn(), %{"query" => "grace"})
  end

  test "requires the support read scope" do
    conn = mcp_conn(insert_user!(%{scopes: ["gtm:read"]}))

    assert {:error, "Email inbox tools require the support:read scope."} =
             execute_tool(ListEmailInbox, conn, %{})
  end
end
