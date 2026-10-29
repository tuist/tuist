defmodule Atlas.MCP.Tools.GetSocialPostRevisionTest do
  use Atlas.MCP.ToolCase

  alias Atlas.GTM
  alias Atlas.MCP.Tools.GetSocialPostRevision

  test "returns a post revision" do
    {:ok, idea} = GTM.create_social_channel_idea(%{"title" => "Get revision"})
    {:ok, revision} = GTM.create_social_post_revision(idea, %{"body" => "Readable draft"})

    {:ok, payload} =
      execute_tool(GetSocialPostRevision, conn_for(nil), %{"social_post_revision_id" => revision.id})

    assert %{
             social_post_revision: %{
               id: id,
               social_channel_idea_id: idea_id,
               body: "Readable draft"
             }
           } = payload

    assert id == revision.id
    assert idea_id == idea.id
  end

  test "returns an error for an unknown revision" do
    assert {:error, "Social post revision not found."} =
             execute_tool(GetSocialPostRevision, conn_for(nil), %{
               "social_post_revision_id" => Ecto.UUID.generate()
             })
  end
end
