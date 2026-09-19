defmodule Atlas.MCP.Tools.RotateProjectErrorDsnTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Engineering.Errors
  alias Atlas.Engineering.Projects
  alias Atlas.MCP.Tools.RotateProjectErrorDsn

  test "rotates the project DSN, invalidating the old key" do
    {:ok, project} = Projects.create_project(%{"name" => "Atlas", "visibility" => "public"})
    {:ok, previous_key} = Errors.create_project_key(project.id)
    user = insert_user!()

    {:ok, %{"key" => key}} =
      execute_tool(RotateProjectErrorDsn, mcp_conn(user), %{"project_id" => project.id})

    assert key["id"] != previous_key.id
    assert is_binary(key["dsn"])
  end

  test "returns an error when the project does not exist" do
    user = insert_user!()

    assert {:error, "Project not found."} =
             execute_tool(RotateProjectErrorDsn, mcp_conn(user), %{
               "project_id" => "00000000-0000-0000-0000-000000000000"
             })
  end
end
