defmodule Atlas.MCP.Tools.ReportHolidayTest do
  use Atlas.MCP.ToolCase

  import Atlas.TimeOffFixtures

  alias Atlas.MCP.Tools.ReportHoliday
  alias Atlas.TimeOff

  test "reports only the caller's leave and validates its structured response" do
    admin = admin_fixture()
    location = location_fixture(admin)
    user = assign_fixture(user_fixture(), location, admin)
    args = %{"starts_on" => "2026-05-01", "ends_on" => "2026-05-05", "user_id" => admin.id}
    assert {:ok, %{booking: booking}} = execute_tool(ReportHoliday, mcp_conn(user), args)
    assert booking.user_id == user.id
    assert booking.status == "pending"
    assert {:error, _} = execute_tool(ReportHoliday, mcp_conn(nil), args)
    new_user = user_fixture()
    assert {:ok, %{booking: first_request}} = execute_tool(ReportHoliday, mcp_conn(new_user), args)
    assert first_request.user_id == new_user.id
    assert first_request.location_id == TimeOff.default_location().id
  end
end
