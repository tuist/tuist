defmodule Atlas.MCP.Tools.GetDomainErrorDsnTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Engineering.Domains
  alias Atlas.Engineering.Errors
  alias Atlas.Engineering.Projects
  alias Atlas.MCP.Tools.GetDomainErrorDsn

  test "returns the DSN for a linked (project, domain) pair" do
    {:ok, project} = Projects.create_project(%{"name" => "Atlas", "visibility" => "public"})
    {:ok, domain} = Domains.create_domain(%{"name" => "Cache", "project_id" => project.id})
    {:ok, minted_key} = Errors.create_domain_key(project.id, domain.id)
    user = insert_user!()

    {:ok, %{"key" => key}} =
      execute_tool(GetDomainErrorDsn, mcp_conn(user), %{
        "project_id" => project.id,
        "domain_id" => domain.id
      })

    assert key["id"] == minted_key.id
  end

  test "returns an error when the domain is not linked to the project" do
    {:ok, project} = Projects.create_project(%{"name" => "Atlas", "visibility" => "public"})
    {:ok, domain} = Domains.create_domain(%{"name" => "Cache"})
    user = insert_user!()

    assert {:error, "Domain is not linked to project."} =
             execute_tool(GetDomainErrorDsn, mcp_conn(user), %{
               "project_id" => project.id,
               "domain_id" => domain.id
             })
  end

  test "returns an error when the project does not exist" do
    user = insert_user!()

    assert {:error, "Project or domain not found."} =
             execute_tool(GetDomainErrorDsn, mcp_conn(user), %{
               "project_id" => "00000000-0000-0000-0000-000000000000",
               "domain_id" => "00000000-0000-0000-0000-000000000000"
             })
  end
end
