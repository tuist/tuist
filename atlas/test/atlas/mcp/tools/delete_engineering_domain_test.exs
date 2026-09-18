defmodule Atlas.MCP.Tools.DeleteEngineeringDomainTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Engineering.Domains
  alias Atlas.MCP.Tools.DeleteEngineeringDomain
  alias Atlas.Repo

  test "deletes a domain and returns a snapshot" do
    {:ok, domain} = Domains.create_domain(%{"name" => "Cache"})
    user = insert_user!()

    {:ok, %{"deleted_domain" => payload}} =
      execute_tool(DeleteEngineeringDomain, mcp_conn(user), %{"id" => domain.id})

    assert payload["id"] == domain.id
    assert Repo.get(Domains.Domain, domain.id) == nil
  end

  test "returns an error when the domain does not exist" do
    user = insert_user!()

    assert {:error, "Domain not found."} =
             execute_tool(DeleteEngineeringDomain, mcp_conn(user), %{
               "id" => "00000000-0000-0000-0000-000000000000"
             })
  end
end
