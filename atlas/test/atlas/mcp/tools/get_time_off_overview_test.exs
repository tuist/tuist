defmodule Atlas.MCP.Tools.GetTimeOffOverviewTest do
  use Atlas.MCP.ToolCase

  import Atlas.TimeOffFixtures

  alias Atlas.MCP.Tools.GetTimeOffOverview
  alias Atlas.TimeOff

  test "returns independent paginated upcoming leave, own history, and public holidays" do
    admin = admin_fixture()
    location = location_fixture(admin)
    user = assign_fixture(user_fixture(), location, admin)
    {:ok, _} = TimeOff.report_holiday(%{starts_on: "2026-04-01", ends_on: "2026-04-05"}, user)
    teammate = assign_fixture(user_fixture(), location, admin)
    {:ok, _} = TimeOff.report_holiday(%{starts_on: "2026-05-01", ends_on: "2026-05-05"}, teammate)
    {:ok, _} = TimeOff.add_holiday(location.id, %{name: "May Day", date: "2026-05-01"}, admin)
    args = %{"from" => "2026-05-01", "location_id" => location.id}
    assert {:ok, response} = execute_tool(GetTimeOffOverview, mcp_conn(user), args)
    assert [%{user_id: teammate_id}] = response.upcoming.items
    assert teammate_id == teammate.id
    assert [%{user_id: user_id}] = response.my_requests.items
    assert user_id == user.id
    assert response.my_requests.total_count == 1
    assert response.my_requests.page == 1
    assert [%{name: "May Day"}] = response.public_holidays.items
    assert {:error, _} = execute_tool(GetTimeOffOverview, mcp_conn(nil), args)
    assert {:error, _} = execute_tool(GetTimeOffOverview, mcp_conn(user), %{"from" => "invalid"})
  end
end
