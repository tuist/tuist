defmodule Atlas.MCP.Tools.UnlinkProjectDomainTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Engineering.Domains
  alias Atlas.Engineering.Projects
  alias Atlas.MCP.Tools.UnlinkProjectDomain

  test "unlinks a domain from a project" do
    {:ok, project} = Projects.create_project(%{"name" => "Atlas", "visibility" => "public"})
    {:ok, domain} = Domains.create_domain(%{"name" => "Cache", "project_id" => project.id})
    user = insert_user!()

    {:ok, %{"project" => payload_project, "unlinked_domain" => payload_domain}} =
      execute_tool(UnlinkProjectDomain, mcp_conn(user), %{
        "project_id" => project.id,
        "domain_id" => domain.id
      })

    refute domain.id in payload_project["domain_ids"]
    assert payload_domain["id"] == domain.id
    assert Projects.get_project!(project.id).domains == []
  end

  test "returns an error when the project does not exist" do
    {:ok, domain} = Domains.create_domain(%{"name" => "Cache"})
    user = insert_user!()

    assert {:error, "Project or domain not found."} =
             execute_tool(UnlinkProjectDomain, mcp_conn(user), %{
               "project_id" => "00000000-0000-0000-0000-000000000000",
               "domain_id" => domain.id
             })
  end
end
