defmodule Atlas.MCP.Tools.AuditToolsTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Audit
  alias Atlas.MCP.Tools.GetAuditActivity
  alias Atlas.MCP.Tools.ListAuditActivities

  test "lists audit activities for executives" do
    {:ok, activity} =
      Audit.log("account.updated", %{
        interface: "dashboard",
        actor_email: "admin@example.com",
        target_type: "account",
        target_id: "account-id",
        target_label: "Account"
      })

    {:ok, _other_activity} =
      Audit.log("blog_post_idea.created", %{
        interface: "slack",
        target_type: "blog_post_idea",
        target_id: "idea-id"
      })

    assert {:ok, payload} =
             execute_tool(ListAuditActivities, executive_mcp_conn(), %{
               "interface" => "dashboard",
               "page_size" => 10
             })

    assert %{activities: [result], pagination: %{total_count: 1}} = payload
    assert result.id == activity.id
    assert result.actor.email == "admin@example.com"
    assert result.target.path == "/commercial/sales/accounts/account-id"
  end

  test "gets a single audit activity for executives" do
    {:ok, activity} =
      Audit.log("document.uploaded", %{
        interface: "mcp",
        target_type: "document",
        target_id: "document-id",
        target_label: "Document"
      })

    assert {:ok, %{activity: result}} =
             execute_tool(GetAuditActivity, executive_mcp_conn(), %{"activity_id" => activity.id})

    assert result.id == activity.id
    assert result.target.path == "/library/documents/document-id"
  end

  test "rejects non-executive users" do
    conn = %{role: :employee} |> insert_user!() |> mcp_conn()

    assert {:error, "Audit tools require the audit:read scope."} =
             execute_tool(ListAuditActivities, conn, %{})

    assert {:error, "Audit tools require the audit:read scope."} =
             execute_tool(GetAuditActivity, conn, %{"activity_id" => Ecto.UUID.generate()})
  end
end
