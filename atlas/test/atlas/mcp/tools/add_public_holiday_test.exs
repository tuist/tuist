defmodule Atlas.MCP.Tools.AddPublicHolidayTest do
  use Atlas.MCP.ToolCase

  import Atlas.TimeOffFixtures

  alias Atlas.MCP.Tools.AddPublicHoliday

  test "only administrators add local holidays and responses conform to the schema" do
    admin = admin_fixture()
    location = location_fixture(admin)
    args = %{"location_id" => location.id, "name" => "Local holiday", "date" => "2026-05-01"}
    assert {:error, _} = execute_tool(AddPublicHoliday, mcp_conn(user_fixture()), args)
    assert {:error, _} = execute_tool(AddPublicHoliday, mcp_conn(nil), args)

    assert {:ok, %{holiday: %{source: "manual", date: "2026-05-01"}}} =
             execute_tool(AddPublicHoliday, mcp_conn(admin), args)
  end
end
