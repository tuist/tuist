defmodule Atlas.MCP.Tools.GetEngineeringDomainTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Engineering.Domains
  alias Atlas.MCP.Tools.GetEngineeringDomain

  test "returns a domain" do
    {:ok, domain} = Domains.create_domain(%{"name" => "Cache", "visibility" => "public"})
    user = insert_user!()

    {:ok, %{"domain" => payload}} =
      execute_tool(GetEngineeringDomain, mcp_conn(user), %{"id" => domain.id})

    assert payload["id"] == domain.id
    assert payload["name"] == "Cache"
    assert payload["project_ids"] == []
  end

  test "returns an error when the domain does not exist" do
    user = insert_user!()

    assert {:error, "Domain not found."} =
             execute_tool(GetEngineeringDomain, mcp_conn(user), %{
               "id" => "00000000-0000-0000-0000-000000000000"
             })
  end
end
