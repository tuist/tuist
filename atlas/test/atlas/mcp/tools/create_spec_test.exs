defmodule Atlas.MCP.Tools.CreateSpecTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Engineering.Projects.Project
  alias Atlas.MCP.Tools.CreateSpec
  alias Atlas.Repo

  defp project! do
    name = "Specs MCP project #{System.unique_integer([:positive])}"

    %Project{}
    |> Project.changeset(%{name: name, visibility: :public})
    |> Repo.insert!()
  end

  test "creates a spec" do
    user = insert_user!()
    project = project!()

    assert {:ok, %{"spec" => spec}} =
             execute_tool(CreateSpec, conn_for(user), %{
               "title" => "Draft",
               "body" => "# Draft\n\nBody.",
               "engineering_project_id" => project.id
             })

    assert spec["title"] == "Draft"
    assert spec["visibility"] == "public"
    assert is_integer(spec["number"])
  end

  test "rejects an unauthenticated caller" do
    project = project!()

    assert {:error, _} =
             execute_tool(CreateSpec, conn_for(nil), %{
               "title" => "x",
               "body" => "# x\n\nbody",
               "engineering_project_id" => project.id
             })
  end
end
