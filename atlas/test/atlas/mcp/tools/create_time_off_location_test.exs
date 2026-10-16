defmodule Atlas.MCP.Tools.CreateTimeOffLocationTest do
  use Atlas.MCP.ToolCase

  import Atlas.TimeOffFixtures

  alias Atlas.MCP.Tools.CreateTimeOffLocation

  test "only administrators create calendars and responses conform to the schema" do
    args = %{
      "name" => "Berlin #{System.unique_integer([:positive])}",
      "country_code" => "DE",
      "subdivision_code" => "DE-BE"
    }

    assert {:error, _} = execute_tool(CreateTimeOffLocation, mcp_conn(user_fixture()), args)
    assert {:error, _} = execute_tool(CreateTimeOffLocation, mcp_conn(nil), args)

    assert {:ok, %{location: %{country_code: "DE", synced_years: []}}} =
             execute_tool(CreateTimeOffLocation, mcp_conn(admin_fixture()), args)
  end
end
