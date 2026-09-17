defmodule Atlas.MCP.Tools.ListSocialPostRevisionsTest do
  use Atlas.MCP.ToolCase

  alias Atlas.GTM
  alias Atlas.MCP.Tools.ListSocialPostRevisions

  test "lists post revisions for an idea" do
    {:ok, idea} = GTM.create_social_channel_idea(%{"title" => "Revision list"})
    {:ok, _first} = GTM.create_social_post_revision(idea, %{"body" => "First"})
    {:ok, _second} = GTM.create_social_post_revision(idea, %{"body" => "Second"})

    {:ok, payload} =
      execute_tool(ListSocialPostRevisions, conn_for(nil), %{"social_channel_idea_id" => idea.id})

    assert %{social_post_revisions: revisions, count: 2} = payload
    assert Enum.map(revisions, & &1.revision_number) == [1, 2]
  end

  test "returns an error for an unknown idea" do
    assert {:error, "Social-channel idea not found."} =
             execute_tool(ListSocialPostRevisions, conn_for(nil), %{
               "social_channel_idea_id" => Ecto.UUID.generate()
             })
  end
end
