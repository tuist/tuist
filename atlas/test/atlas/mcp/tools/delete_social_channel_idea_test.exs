defmodule Atlas.MCP.Tools.DeleteSocialChannelIdeaTest do
  use Atlas.MCP.ToolCase

  alias Atlas.GTM
  alias Atlas.MCP.Tools.DeleteSocialChannelIdea

  test "deletes an existing social-channel idea" do
    {:ok, idea} = GTM.create_social_channel_idea(%{"title" => "Delete through tool"})

    {:ok, payload} =
      execute_tool(DeleteSocialChannelIdea, conn_for(nil), %{
        "social_channel_idea_id" => idea.id
      })

    assert %{deleted: true, social_channel_idea: %{id: id}} = payload
    assert id == idea.id
    refute GTM.get_social_channel_idea(idea.id)
  end

  test "returns an error for an unknown idea" do
    assert {:error, "Social-channel idea not found."} =
             execute_tool(DeleteSocialChannelIdea, conn_for(nil), %{
               "social_channel_idea_id" => Ecto.UUID.generate()
             })
  end
end
