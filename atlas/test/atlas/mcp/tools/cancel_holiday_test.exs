defmodule Atlas.MCP.Tools.CancelHolidayTest do
  use Atlas.MCP.ToolCase

  import Atlas.TimeOffFixtures

  alias Atlas.MCP.Tools.CancelHoliday
  alias Atlas.TimeOff

  test "cancels only the caller's booking and validates its structured response" do
    admin = admin_fixture()
    location = location_fixture(admin)
    user = assign_fixture(user_fixture(), location, admin)
    {:ok, booking} = TimeOff.report_holiday(%{starts_on: "2026-05-01", ends_on: "2026-05-05"}, user)
    args = %{"id" => booking.id}
    assert {:error, _} = execute_tool(CancelHoliday, mcp_conn(admin), args)
    assert {:error, _} = execute_tool(CancelHoliday, mcp_conn(nil), args)
    assert {:ok, %{booking: %{status: "cancelled"}}} = execute_tool(CancelHoliday, mcp_conn(user), args)
  end
end
