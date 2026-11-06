defmodule Atlas.MCP.Tools.MyProfileTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Audit.Activity
  alias Atlas.MCP.Server
  alias Atlas.MCP.Tools.GetMyProfile
  alias Atlas.MCP.Tools.UpdateMyProfile
  alias Atlas.Orbit.ToolPolicy
  alias Atlas.Users

  test "self tools round-trip only caller description, validate schema, and can clear with a stale caller" do
    user = insert_user!()
    other = insert_user!()
    conn = mcp_conn(user)
    assert {:ok, %{description: ""}} = execute_tool(GetMyProfile, conn, %{})

    assert {:ok, %{description: "Leader\nThoughtful"}} =
             execute_tool(UpdateMyProfile, conn, %{"description" => "Leader\nThoughtful"})

    assert {:ok, %{description: "Leader\nThoughtful"}} = execute_tool(GetMyProfile, conn, %{})
    assert Users.get_user(other.id).description == ""
    assert Users.get_user(user.id).email == user.email
    assert {:ok, %{description: ""}} = execute_tool(UpdateMyProfile, conn, %{"description" => ""})
    assert :error = ToolPolicy.required_scopes("update_my_profile")
    assert :error = ToolPolicy.required_scopes("get_my_profile")
  end

  test "authentication, selectors, extra fields and malformed/oversized text are rejected" do
    conn = insert_user!() |> mcp_conn()
    assert {:error, _} = execute_tool(GetMyProfile, %{assigns: %{}}, %{})
    assert {:error, _} = execute_tool(UpdateMyProfile, %{assigns: %{}}, %{"description" => "no"})
    assert {:error, _} = execute_tool(GetMyProfile, conn, %{"user_id" => "another"})

    for args <- [
          %{},
          %{"description" => nil},
          %{"description" => []},
          %{"description" => String.duplicate("🦀", 4001)},
          %{"description" => "no", "user_id" => "another"},
          %{"description" => "no", "name" => "Changed"}
        ] do
      assert {:error, _} = execute_tool(UpdateMyProfile, conn, args)
    end
  end

  test "profile text never enters MCP or domain audit metadata, including failed input" do
    conn = insert_user!() |> mcp_conn()

    for args <- [%{"description" => "private personality"}, %{"description" => "private personality", "bad" => true}] do
      Server.handle_message(conn, %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "update_my_profile", "arguments" => args}
      })
    end

    activities = Repo.all(Activity)
    refute inspect(activities) =~ "private personality"
    assert Enum.count(activities, &(&1.action == "mcp.tool_called")) == 2
    assert Enum.any?(activities, &(&1.action == "user.profile_updated"))
  end
end
