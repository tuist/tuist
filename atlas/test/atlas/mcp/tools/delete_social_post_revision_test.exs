defmodule Atlas.MCP.Tools.DeleteSocialPostRevisionTest do
  use Atlas.MCP.ToolCase

  alias Atlas.GTM
  alias Atlas.GTM.SocialPostRevision
  alias Atlas.MCP.Tools.DeleteSocialPostRevision
  alias Atlas.Repo

  test "deletes a post revision" do
    {:ok, idea} = GTM.create_social_channel_idea(%{"title" => "Delete revision"})
    {:ok, revision} = GTM.create_social_post_revision(idea, %{"body" => "Delete me"})

    {:ok, payload} =
      execute_tool(DeleteSocialPostRevision, conn_for(nil), %{"social_post_revision_id" => revision.id})

    assert %{deleted: true, social_post_revision: %{id: id}} = payload
    assert id == revision.id
    refute Repo.get(SocialPostRevision, revision.id)
  end

  test "returns an error for an unknown revision" do
    assert {:error, "Social post revision not found."} =
             execute_tool(DeleteSocialPostRevision, conn_for(nil), %{
               "social_post_revision_id" => Ecto.UUID.generate()
             })
  end
end
