defmodule Atlas.MCP.Tools.SearchApolloOutreachTest do
  use Atlas.MCP.ToolCase

  alias Atlas.MCP.Tools.SearchApolloOutreach

  test "reports when Apollo is not configured" do
    assert {:error, "Apollo is not configured for this environment."} =
             execute_tool(SearchApolloOutreach, mcp_conn(nil), %{})
  end
end
