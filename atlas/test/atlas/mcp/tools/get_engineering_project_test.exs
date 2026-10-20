defmodule Atlas.MCP.Tools.GetEngineeringProjectTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Engineering.Projects
  alias Atlas.MCP.Tools.GetEngineeringProject

  test "returns a project by id" do
    {:ok, project} = Projects.create_project(%{"name" => "Atlas", "visibility" => "public"})
    user = insert_user!()

    {:ok, %{"project" => payload}} =
      execute_tool(GetEngineeringProject, mcp_conn(user), %{"id" => project.id})

    assert payload["id"] == project.id
    assert payload["name"] == "Atlas"
    assert payload["domain_ids"] == []
    assert payload["repositories"] == []
  end

  test "returns an error when the project does not exist" do
    user = insert_user!()

    assert {:error, "Project not found."} =
             execute_tool(GetEngineeringProject, mcp_conn(user), %{
               "id" => "00000000-0000-0000-0000-000000000000"
             })
  end
end
