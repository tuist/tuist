defmodule Atlas.MCP.Tools.AssignTimeOffLocationTest do
  use Atlas.MCP.ToolCase

  import Atlas.TimeOffFixtures

  alias Atlas.MCP.Tools.AssignTimeOffLocation

  test "only administrators assign calendars and responses conform to the schema" do
    admin = admin_fixture()
    user = user_fixture()
    location = location_fixture(admin)
    args = %{"user_id" => user.id, "location_id" => location.id}
    assert {:error, _} = execute_tool(AssignTimeOffLocation, mcp_conn(user), args)
    assert {:error, _} = execute_tool(AssignTimeOffLocation, mcp_conn(nil), args)
    assert {:ok, %{user_id: id, location_id: location_id}} = execute_tool(AssignTimeOffLocation, mcp_conn(admin), args)
    assert id == user.id
    assert location_id == location.id
  end
end
