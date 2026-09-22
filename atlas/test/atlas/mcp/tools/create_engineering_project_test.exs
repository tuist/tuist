defmodule Atlas.MCP.Tools.CreateEngineeringProjectTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Engineering.Projects
  alias Atlas.MCP.Tools.CreateEngineeringProject

  test "creates a project" do
    user = insert_user!()

    {:ok, %{"project" => project}} =
      execute_tool(CreateEngineeringProject, mcp_conn(user), %{
        "name" => "Atlas",
        "description" => "Ops app.",
        "visibility" => "public"
      })

    assert project["name"] == "Atlas"
    assert project["description"] == "Ops app."
    assert project["visibility"] == "public"
    assert Projects.get_project!(project["id"]).name == "Atlas"
  end

  test "rejects an invalid name" do
    user = insert_user!()

    assert {:error, message} =
             execute_tool(CreateEngineeringProject, mcp_conn(user), %{
               "name" => String.duplicate("a", 200)
             })

    assert message =~ "Could not create project"
  end
end
