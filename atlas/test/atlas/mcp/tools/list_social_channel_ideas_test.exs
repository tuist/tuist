defmodule Atlas.MCP.Tools.ListSocialChannelIdeasTest do
  use Atlas.MCP.ToolCase

  alias Atlas.GTM
  alias Atlas.MCP.Tools.ListSocialChannelIdeas

  test "lists ideas with a count" do
    {:ok, _} = GTM.create_social_channel_idea(%{"title" => "First social idea"})
    {:ok, _} = GTM.create_social_channel_idea(%{"title" => "Published social idea", "status" => "approved"})

    {:ok, payload} = execute_tool(ListSocialChannelIdeas, conn_for(nil), %{})

    assert %{social_channel_ideas: ideas, count: 2} = payload
    assert "First social idea" in Enum.map(ideas, & &1.title)
    assert "Published social idea" in Enum.map(ideas, & &1.title)
  end

  test "returns an empty list when there are no ideas" do
    assert {:ok, %{social_channel_ideas: [], count: 0}} = execute_tool(ListSocialChannelIdeas, conn_for(nil), %{})
  end
end
