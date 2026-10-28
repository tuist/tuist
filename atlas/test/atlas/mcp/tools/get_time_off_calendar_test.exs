defmodule Atlas.MCP.Tools.GetTimeOffCalendarTest do
  use Atlas.MCP.ToolCase
  use Mimic

  import Atlas.TimeOffFixtures

  alias Atlas.MCP.Proxy
  alias Atlas.MCP.Server
  alias Atlas.MCP.Tools.GetTimeOffCalendar
  alias Atlas.TimeOff

  test "returns schema-checked availability, location coverage, and current assignments" do
    admin = admin_fixture()
    location = location_fixture(admin)
    user = assign_fixture(user_fixture(), location, admin)
    {:ok, _booking} = TimeOff.report_holiday(%{starts_on: "2026-05-01", ends_on: "2026-05-05"}, user)
    {:ok, _holiday} = TimeOff.add_holiday(location.id, %{name: "May Day", date: "2026-05-01"}, admin)
    args = %{"starts_on" => "2026-05-01", "ends_on" => "2026-05-31"}

    assert {:ok, %{bookings: [%{working_days: 2}], public_holidays: [_], locations: [_, _]}} =
             execute_tool(GetTimeOffCalendar, mcp_conn(user), args)

    assert {:error, _} = execute_tool(GetTimeOffCalendar, mcp_conn(nil), args)
    assert {:error, _} = execute_tool(GetTimeOffCalendar, mcp_conn(user), %{args | "starts_on" => "bad"})
    assert {:error, _} = execute_tool(GetTimeOffCalendar, mcp_conn(user), %{args | "ends_on" => "2027-01-01"})
  end

  test "calendar and reporting tools are discoverable by employees but setup tools are admin-only" do
    stub(Proxy, :list_hoisted_tools, fn _conn -> [] end)
    employee_tools = tool_names(user_fixture())
    assert "get_time_off_calendar" in employee_tools
    assert "get_time_off_overview" in employee_tools
    assert "update_holiday" in employee_tools
    assert "report_holiday" in employee_tools
    assert "cancel_holiday" in employee_tools
    refute "create_time_off_location" in employee_tools
    refute "review_holiday" in employee_tools
    admin_tools = tool_names(admin_fixture())
    assert "create_time_off_location" in admin_tools
    assert "import_public_holidays" in admin_tools
    assert "review_holiday" in admin_tools

    approver = user_fixture()
    AtlasWeb.ConnCase.assign_role_or_scopes(approver, nil, ["time_off_approvals:write"])
    assert "review_holiday" in tool_names(approver)
    refute "create_time_off_location" in tool_names(approver)
  end

  defp tool_names(user) do
    response = Server.handle_message(mcp_conn(user), %{"jsonrpc" => "2.0", "method" => "tools/list", "id" => 1})
    Enum.map(response["result"]["tools"], & &1["name"])
  end
end
