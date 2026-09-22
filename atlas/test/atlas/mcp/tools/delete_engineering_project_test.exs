defmodule Atlas.MCP.Tools.DeleteEngineeringProjectTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Engineering.Projects
  alias Atlas.MCP.Tools.DeleteEngineeringProject
  alias Atlas.Repo

  test "deletes a project and returns a snapshot" do
    {:ok, project} = Projects.create_project(%{"name" => "Atlas", "visibility" => "public"})
    user = insert_user!()

    {:ok, %{"deleted_project" => payload}} =
      execute_tool(DeleteEngineeringProject, mcp_conn(user), %{"id" => project.id})

    assert payload["id"] == project.id
    assert Repo.get(Projects.Project, project.id) == nil
  end

  test "returns an error when the project does not exist" do
    user = insert_user!()

    assert {:error, "Project not found."} =
             execute_tool(DeleteEngineeringProject, mcp_conn(user), %{
               "id" => "00000000-0000-0000-0000-000000000000"
             })
  end
end
