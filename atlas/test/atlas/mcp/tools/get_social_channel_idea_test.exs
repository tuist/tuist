defmodule Atlas.MCP.Tools.GetSocialChannelIdeaTest do
  use Atlas.MCP.ToolCase

  alias Atlas.GTM
  alias Atlas.MCP.Tools.GetSocialChannelIdea

  test "returns an idea" do
    {:ok, idea} =
      GTM.create_social_channel_idea(%{
        "title" => "Social deep dive"
      })

    {:ok, _revision} = GTM.create_social_post_revision(idea, %{"body" => "First draft"})

    {:ok, payload} =
      execute_tool(GetSocialChannelIdea, conn_for(nil), %{"social_channel_idea_id" => idea.id})

    assert %{
             social_channel_idea: %{
               id: id,
               title: "Social deep dive",
               post_revisions: [%{body: "First draft", revision_number: 1}]
             }
           } = payload

    assert id == idea.id
  end

  test "returns an error for an unknown idea" do
    assert {:error, "Social-channel idea not found."} =
             execute_tool(GetSocialChannelIdea, conn_for(nil), %{"social_channel_idea_id" => Ecto.UUID.generate()})
  end
end
