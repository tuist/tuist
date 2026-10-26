defmodule Atlas.MCP.Tools.ImportPublicHolidaysTest do
  use Atlas.MCP.ToolCase
  use Mimic

  import Atlas.TimeOffFixtures

  alias Atlas.MCP.Tools.ImportPublicHolidays
  alias Atlas.TimeOff.PublicHolidays

  test "only administrators import dates and responses conform to the schema" do
    admin = admin_fixture()
    location = location_fixture(admin)
    args = %{"location_id" => location.id, "year" => 2026}
    assert {:error, _} = execute_tool(ImportPublicHolidays, mcp_conn(user_fixture()), args)
    assert {:error, _} = execute_tool(ImportPublicHolidays, mcp_conn(nil), args)
    expect(PublicHolidays, :fetch, fn _location, 2026 -> {:ok, [%{date: ~D[2026-05-01], name: "May Day"}]} end)
    assert {:ok, %{location: %{synced_years: [2026]}}} = execute_tool(ImportPublicHolidays, mcp_conn(admin), args)
  end
end
