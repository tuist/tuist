defmodule Atlas.MCP.Tools.ListEngineeringDomainsTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Engineering.Domains
  alias Atlas.MCP.Tools.ListEngineeringDomains

  test "returns [] when no domains exist" do
    user = insert_user!()
    {:ok, %{"domains" => []}} = execute_tool(ListEngineeringDomains, mcp_conn(user), %{})
  end

  test "lists every visible domain" do
    {:ok, cache} = Domains.create_domain(%{"name" => "Cache", "visibility" => "public"})
    user = insert_user!()

    {:ok, %{"domains" => domains}} = execute_tool(ListEngineeringDomains, mcp_conn(user), %{})

    assert Enum.any?(domains, &(&1["id"] == cache.id))
  end
end
