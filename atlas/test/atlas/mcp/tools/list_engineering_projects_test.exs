defmodule Atlas.MCP.Tools.ListEngineeringProjectsTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Engineering.Projects
  alias Atlas.MCP.Tools.ListEngineeringProjects

  test "returns [] when no projects exist" do
    user = insert_user!()
    {:ok, %{"projects" => []}} = execute_tool(ListEngineeringProjects, mcp_conn(user), %{})
  end

  test "lists every visible project" do
    {:ok, atlas} = Projects.create_project(%{"name" => "Atlas", "visibility" => "public"})
    {:ok, tuist} = Projects.create_project(%{"name" => "Tuist", "visibility" => "private"})

    user = insert_user!()
    {:ok, %{"projects" => projects}} = execute_tool(ListEngineeringProjects, mcp_conn(user), %{})

    ids = Enum.map(projects, & &1["id"])
    assert atlas.id in ids
    assert tuist.id in ids
  end
end
