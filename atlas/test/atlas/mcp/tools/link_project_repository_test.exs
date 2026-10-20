defmodule Atlas.MCP.Tools.LinkProjectRepositoryTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Engineering.Projects
  alias Atlas.MCP.Tools.LinkProjectRepository

  test "links a repository to a project" do
    {:ok, project} = Projects.create_project(%{"name" => "Atlas", "visibility" => "public"})
    user = insert_user!()

    {:ok, %{"project" => payload_project, "repository" => payload_repository}} =
      execute_tool(LinkProjectRepository, mcp_conn(user), %{
        "project_id" => project.id,
        "owner" => "tuist",
        "name" => "atlas"
      })

    assert "tuist/atlas" in payload_project["repositories"]
    assert payload_repository["owner"] == "tuist"
    assert payload_repository["name"] == "atlas"
  end

  test "returns an error when the project does not exist" do
    user = insert_user!()

    assert {:error, "Project not found."} =
             execute_tool(LinkProjectRepository, mcp_conn(user), %{
               "project_id" => "00000000-0000-0000-0000-000000000000",
               "owner" => "tuist",
               "name" => "atlas"
             })
  end
end
