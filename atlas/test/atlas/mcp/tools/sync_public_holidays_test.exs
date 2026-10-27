defmodule Atlas.MCP.Tools.SyncPublicHolidaysTest do
  use Atlas.MCP.ToolCase
  use Mimic

  import Atlas.TimeOffFixtures

  alias Atlas.MCP.Proxy
  alias Atlas.MCP.Server
  alias Atlas.MCP.Tools.SyncPublicHolidays
  alias Atlas.TimeOff.PublicHolidays

  test "Atlas MCP exposes holiday read and owner actions, while sync requires admin write" do
    user = user_fixture()
    admin = admin_fixture()
    conn = mcp_conn(admin)
    stub(Proxy, :list_hoisted_tools, fn _conn -> [] end)
    names = tool_names(mcp_conn(user))
    assert "get_time_off_overview" in names
    assert "report_holiday" in names
    assert "update_holiday" in names
    assert "cancel_holiday" in names
    refute "review_holiday" in names
    refute "sync_public_holidays" in names
    assert "sync_public_holidays" in tool_names(conn)
    assert {:error, _} = execute_tool(SyncPublicHolidays, mcp_conn(nil), %{})
    assert {:error, _} = execute_tool(SyncPublicHolidays, mcp_conn(user), %{})
    stub(PublicHolidays, :fetch, fn _location, year -> {:ok, [%{name: "Holiday", date: Date.new!(year, 1, 1)}]} end)
    assert {:ok, %{location: location}} = execute_tool(SyncPublicHolidays, conn, %{})
    assert location.name == "Berlin"
    assert location.subdivision_code == "DE-BE"
    assert Date.utc_today().year in location.synced_years
  end

  defp tool_names(conn) do
    response = Server.handle_message(conn, %{"jsonrpc" => "2.0", "method" => "tools/list", "id" => 1})
    Enum.map(response["result"]["tools"], & &1["name"])
  end
end
