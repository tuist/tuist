defmodule Atlas.MCP.Tools.CreateSocialChannelIdeaTest do
  use Atlas.MCP.ToolCase

  alias Atlas.GTM
  alias Atlas.MCP.Tools.CreateSocialChannelIdea

  test "captures a social-channel idea attributed to the current user" do
    user = insert_user!(%{name: "Casey Social"})

    {:ok, payload} =
      execute_tool(CreateSocialChannelIdea, conn_for(user), %{
        "title" => "Turn the benchmark into a LinkedIn carousel",
        "description" => "Use the cache chart and call out saved build time."
      })

    assert %{
             social_channel_idea: %{
               id: id,
               title: "Turn the benchmark into a LinkedIn carousel",
               status: "idea"
             }
           } = payload

    assert is_binary(id)

    idea = GTM.get_social_channel_idea(id)
    assert idea.created_by_agent == "mcp"
    assert idea.author_id == user.id
  end

  test "accepts an explicit status" do
    {:ok, payload} =
      execute_tool(CreateSocialChannelIdea, conn_for(nil), %{
        "title" => "Already approved",
        "status" => "approved"
      })

    assert %{social_channel_idea: %{status: "approved"}} = payload
  end

  test "rejects a blank title" do
    assert {:error, message} = execute_tool(CreateSocialChannelIdea, conn_for(nil), %{"title" => "   "})
    assert message =~ "Could not create social-channel idea"
  end
end
