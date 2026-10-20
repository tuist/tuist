defmodule Atlas.MCP.Tools.LinkProjectDomainTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Engineering.Domains
  alias Atlas.Engineering.Projects
  alias Atlas.MCP.Tools.LinkProjectDomain

  test "links a domain to a project" do
    {:ok, project} = Projects.create_project(%{"name" => "Atlas", "visibility" => "public"})
    {:ok, domain} = Domains.create_domain(%{"name" => "Cache"})
    user = insert_user!()

    {:ok, %{"project" => payload_project, "domain" => payload_domain}} =
      execute_tool(LinkProjectDomain, mcp_conn(user), %{
        "project_id" => project.id,
        "domain_id" => domain.id
      })

    assert domain.id in payload_project["domain_ids"]
    assert project.id in payload_domain["project_ids"]
  end

  test "returns an error when the project does not exist" do
    {:ok, domain} = Domains.create_domain(%{"name" => "Cache"})
    user = insert_user!()

    assert {:error, "Project or domain not found."} =
             execute_tool(LinkProjectDomain, mcp_conn(user), %{
               "project_id" => "00000000-0000-0000-0000-000000000000",
               "domain_id" => domain.id
             })
  end
end
