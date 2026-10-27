defmodule Atlas.MCP.Tools.UpdateEngineeringProjectTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Engineering.Projects
  alias Atlas.MCP.Tools.UpdateEngineeringProject

  test "updates a project" do
    {:ok, project} = Projects.create_project(%{"name" => "Atlas", "visibility" => "public"})
    user = insert_user!()

    {:ok, %{"project" => payload}} =
      execute_tool(UpdateEngineeringProject, mcp_conn(user), %{
        "id" => project.id,
        "name" => "Atlas Cloud",
        "description" => "Ops."
      })

    assert payload["name"] == "Atlas Cloud"
    assert payload["description"] == "Ops."
    assert Projects.get_project!(project.id).name == "Atlas Cloud"
  end

  test "returns an error for an unknown id" do
    user = insert_user!()

    assert {:error, "Project not found."} =
             execute_tool(UpdateEngineeringProject, mcp_conn(user), %{
               "id" => "00000000-0000-0000-0000-000000000000",
               "name" => "Nope"
             })
  end

  test "returns validation errors" do
    {:ok, project} = Projects.create_project(%{"name" => "Atlas", "visibility" => "public"})
    user = insert_user!()

    assert {:error, message} =
             execute_tool(UpdateEngineeringProject, mcp_conn(user), %{
               "id" => project.id,
               "name" => ""
             })

    assert message =~ "Could not update project"
  end
end
