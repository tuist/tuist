defmodule Atlas.MCP.Tools.RemovePublicHolidayTest do
  use Atlas.MCP.ToolCase

  import Atlas.TimeOffFixtures

  alias Atlas.MCP.Tools.RemovePublicHoliday
  alias Atlas.TimeOff

  test "only administrators remove holidays and responses conform to the schema" do
    admin = admin_fixture()
    location = location_fixture(admin)
    {:ok, holiday} = TimeOff.add_holiday(location.id, %{name: "Local holiday", date: "2026-05-01"}, admin)
    args = %{"id" => holiday.id}
    assert {:error, _} = execute_tool(RemovePublicHoliday, mcp_conn(user_fixture()), args)
    assert {:error, _} = execute_tool(RemovePublicHoliday, mcp_conn(nil), args)
    assert {:ok, %{holiday: %{source: "manual"}}} = execute_tool(RemovePublicHoliday, mcp_conn(admin), args)
  end
end
