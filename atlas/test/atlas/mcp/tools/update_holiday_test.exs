defmodule Atlas.MCP.Tools.UpdateHolidayTest do
  use Atlas.MCP.ToolCase

  import Atlas.TimeOffFixtures

  alias Atlas.MCP.Tools.UpdateHoliday
  alias Atlas.TimeOff

  test "only the owner can edit, and edited approved requests require approval again" do
    admin = admin_fixture()
    user = assign_fixture(user_fixture(), location_fixture(admin), admin)
    {:ok, booking} = TimeOff.report_holiday(%{starts_on: "2026-05-01", ends_on: "2026-05-05"}, user)
    {:ok, _} = TimeOff.review_holiday(booking.id, "approved", admin)
    args = %{"id" => booking.id, "starts_on" => "2026-05-11", "ends_on" => "2026-05-15"}
    assert {:error, _} = execute_tool(UpdateHoliday, mcp_conn(nil), args)
    assert {:error, _} = execute_tool(UpdateHoliday, mcp_conn(admin), args)
    assert {:ok, %{booking: updated}} = execute_tool(UpdateHoliday, mcp_conn(user), args)
    assert updated.status == "pending"
    assert updated.reviewed_by_id == nil
    assert updated.reviewed_at == nil
    assert updated.starts_on == "2026-05-11"
  end
end
