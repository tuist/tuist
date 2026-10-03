defmodule Atlas.MCP.Tools.UpdateEngineeringDomainTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Engineering.Domains
  alias Atlas.MCP.Tools.UpdateEngineeringDomain

  test "updates a domain" do
    {:ok, domain} = Domains.create_domain(%{"name" => "Cache"})
    user = insert_user!()

    {:ok, %{"domain" => payload}} =
      execute_tool(UpdateEngineeringDomain, mcp_conn(user), %{
        "id" => domain.id,
        "description" => "Build cache."
      })

    assert payload["description"] == "Build cache."
    assert Domains.get_domain!(domain.id).description == "Build cache."
  end

  test "returns an error when the domain does not exist" do
    user = insert_user!()

    assert {:error, "Domain not found."} =
             execute_tool(UpdateEngineeringDomain, mcp_conn(user), %{
               "id" => "00000000-0000-0000-0000-000000000000",
               "name" => "Nope"
             })
  end
end
