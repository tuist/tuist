defmodule Atlas.MCP.Tools.ReviewHolidayTest do
  use Atlas.MCP.ToolCase

  import Atlas.TimeOffFixtures

  alias Atlas.MCP.Tools.ReviewHoliday
  alias Atlas.TimeOff

  test "only permitted approvers can review, and responses include reviewer metadata" do
    admin = admin_fixture()
    user = assign_fixture(user_fixture(), location_fixture(admin), admin)
    {:ok, booking} = TimeOff.report_holiday(%{starts_on: "2026-05-01", ends_on: "2026-05-05"}, user)
    args = %{"id" => booking.id, "decision" => "approved"}
    assert {:error, _} = execute_tool(ReviewHoliday, mcp_conn(nil), args)
    assert {:error, _} = execute_tool(ReviewHoliday, mcp_conn(user), args)
    assert {:ok, %{booking: approved}} = execute_tool(ReviewHoliday, mcp_conn(admin), args)
    assert approved.status == "approved"
    assert approved.reviewed_by_id == admin.id
    assert is_binary(approved.reviewed_at)
    assert {:error, _} = execute_tool(ReviewHoliday, mcp_conn(admin), %{args | "decision" => "rejected"})
  end

  test "a delegated approver without administrator rights can reject requests" do
    admin = admin_fixture()
    user = assign_fixture(user_fixture(), location_fixture(admin), admin)
    approver = insert_user!(%{scopes: ["time_off_approvals:write"]})
    {:ok, booking} = TimeOff.report_holiday(%{starts_on: "2026-05-01", ends_on: "2026-05-05"}, user)

    assert {:ok, %{booking: %{status: "rejected"}}} =
             execute_tool(ReviewHoliday, mcp_conn(approver), %{"id" => booking.id, "decision" => "rejected"})
  end
end
