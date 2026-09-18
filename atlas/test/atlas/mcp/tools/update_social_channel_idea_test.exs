defmodule Atlas.MCP.Tools.UpdateSocialChannelIdeaTest do
  use Atlas.MCP.ToolCase

  alias Atlas.GTM
  alias Atlas.MCP.Tools.UpdateSocialChannelIdea

  test "updates an existing social-channel idea" do
    {:ok, idea} = GTM.create_social_channel_idea(%{"title" => "Social draft"})

    {:ok, payload} =
      execute_tool(UpdateSocialChannelIdea, conn_for(nil), %{
        "social_channel_idea_id" => idea.id,
        "title" => "Published social post",
        "description" => "Ready to share externally.",
        "status" => "approved"
      })

    assert %{
             social_channel_idea: %{
               id: id,
               title: "Published social post",
               description: "Ready to share externally.",
               status: "approved"
             }
           } = payload

    assert id == idea.id
    assert GTM.get_social_channel_idea(idea.id).status == "approved"
  end

  test "returns an error for an unknown idea" do
    assert {:error, "Social-channel idea not found."} =
             execute_tool(UpdateSocialChannelIdea, conn_for(nil), %{
               "social_channel_idea_id" => Ecto.UUID.generate(),
               "status" => "approved"
             })
  end

  test "rejects an invalid status" do
    {:ok, idea} = GTM.create_social_channel_idea(%{"title" => "Invalid status"})

    assert {:error, message} =
             execute_tool(UpdateSocialChannelIdea, conn_for(nil), %{
               "social_channel_idea_id" => idea.id,
               "status" => "scheduled"
             })

    assert message =~ "Could not update social-channel idea"
  end
end
