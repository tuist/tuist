defmodule Atlas.MCP.Tools.CreateEngineeringDomainTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Engineering.Domains
  alias Atlas.MCP.Tools.CreateEngineeringDomain

  test "creates a domain" do
    user = insert_user!()

    {:ok, %{"domain" => payload}} =
      execute_tool(CreateEngineeringDomain, mcp_conn(user), %{
        "name" => "Cache",
        "description" => "Cache work",
        "visibility" => "public"
      })

    assert payload["name"] == "Cache"
    assert payload["description"] == "Cache work"
    assert Domains.get_domain!(payload["id"]).name == "Cache"
  end

  test "rejects an invalid name" do
    user = insert_user!()

    assert {:error, message} =
             execute_tool(CreateEngineeringDomain, mcp_conn(user), %{
               "name" => String.duplicate("a", 200)
             })

    assert message =~ "Could not create domain"
  end
end
