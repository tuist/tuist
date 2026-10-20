defmodule Atlas.MCP.Tools.RotateDomainErrorDsnTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Engineering.Domains
  alias Atlas.Engineering.Errors
  alias Atlas.Engineering.Projects
  alias Atlas.MCP.Tools.RotateDomainErrorDsn

  test "rotates the DSN for a linked (project, domain) pair" do
    {:ok, project} = Projects.create_project(%{"name" => "Atlas", "visibility" => "public"})
    {:ok, domain} = Domains.create_domain(%{"name" => "Cache", "project_id" => project.id})
    {:ok, previous_key} = Errors.create_domain_key(project.id, domain.id)
    user = insert_user!()

    {:ok, %{"key" => key}} =
      execute_tool(RotateDomainErrorDsn, mcp_conn(user), %{
        "project_id" => project.id,
        "domain_id" => domain.id
      })

    assert key["id"] != previous_key.id
  end

  test "returns an error when the domain is not linked to the project" do
    {:ok, project} = Projects.create_project(%{"name" => "Atlas", "visibility" => "public"})
    {:ok, domain} = Domains.create_domain(%{"name" => "Cache"})
    user = insert_user!()

    assert {:error, "Domain is not linked to project."} =
             execute_tool(RotateDomainErrorDsn, mcp_conn(user), %{
               "project_id" => project.id,
               "domain_id" => domain.id
             })
  end
end
