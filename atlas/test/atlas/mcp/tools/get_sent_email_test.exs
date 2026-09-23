defmodule Atlas.MCP.Tools.GetSentEmailTest do
  use Atlas.MCP.ToolCase

  import Atlas.MailboxFixtures

  alias Atlas.MCP.Tools.GetSentEmail

  test "returns a sent email with its body" do
    delivery = insert_delivery!(%{metadata: %{"body_markdown" => "Your price changes next month."}})

    assert {:ok, %{email: email}} = execute_tool(GetSentEmail, executive_mcp_conn(), %{"id" => delivery.id})

    assert email.id == delivery.id
    assert email.kind == "direct"
    assert email.body_markdown == "Your price changes next month."
  end

  test "returns an error for an unknown id" do
    assert {:error, "Sent email not found."} =
             execute_tool(GetSentEmail, executive_mcp_conn(), %{"id" => Ecto.UUID.generate()})
  end

  test "requires the support read scope" do
    conn = mcp_conn(insert_user!(%{scopes: ["gtm:read"]}))
    delivery = insert_delivery!()

    assert {:error, "Email outbox tools require the support:read scope."} =
             execute_tool(GetSentEmail, conn, %{"id" => delivery.id})
  end
end
