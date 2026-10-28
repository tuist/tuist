defmodule Atlas.MCP.Tools.GetSpecTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Engineering.Projects.Project
  alias Atlas.Engineering.Specs
  alias Atlas.MCP.Tools.GetSpec
  alias Atlas.Repo

  defp project! do
    name = "Specs MCP project #{System.unique_integer([:positive])}"

    %Project{}
    |> Project.changeset(%{name: name, visibility: :public})
    |> Repo.insert!()
  end

  test "fetches a spec by public number" do
    user = insert_user!()
    project = project!()

    {:ok, spec} =
      Specs.create_spec(
        %{
          "title" => "Findable",
          "body" => "# Findable\n\nBody.",
          "engineering_project_id" => project.id
        },
        user
      )

    assert {:ok, %{"spec" => payload}} =
             execute_tool(GetSpec, conn_for(user), %{"id" => to_string(spec.number)})

    assert payload["id"] == spec.id
  end

  test "returns not_found for a missing reference" do
    assert {:error, "Spec not found."} =
             execute_tool(GetSpec, conn_for(nil), %{"id" => "9999999"})
  end
end
