defmodule Atlas.MCP.Tools.CreatePostmortemTest do
  use Atlas.MCP.ToolCase

  alias Atlas.MCP.Tools.CreatePostmortem

  test "publishes a postmortem" do
    user = insert_user!()

    assert {:ok, %{"postmortem" => postmortem}} =
             execute_tool(CreatePostmortem, conn_for(user), %{
               "body" => "# Incident\n\nThe queue backed up."
             })

    assert postmortem["title"] == "Incident"
    assert is_nil(postmortem["share_token"])
    assert is_integer(postmortem["number"])
  end

  test "rejects an unauthenticated caller" do
    assert {:error, _} =
             execute_tool(CreatePostmortem, conn_for(nil), %{"body" => "# x\n\nyy"})
  end
end
