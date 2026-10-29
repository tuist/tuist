defmodule Atlas.MCP.Tools.UpdateSocialPostRevisionTest do
  use Atlas.MCP.ToolCase

  alias Atlas.GTM
  alias Atlas.MCP.Tools.UpdateSocialPostRevision

  test "updates and approves a post revision" do
    {:ok, idea} = GTM.create_social_channel_idea(%{"title" => "Update revision"})
    {:ok, revision} = GTM.create_social_post_revision(idea, %{"body" => "First draft"})

    {:ok, payload} =
      execute_tool(UpdateSocialPostRevision, conn_for(nil), %{
        "social_post_revision_id" => revision.id,
        "body" => "Final draft",
        "notes" => "Ready.",
        "status" => "approved"
      })

    assert %{
             social_post_revision: %{
               id: id,
               body: "Final draft",
               notes: "Ready.",
               status: "approved"
             }
           } = payload

    assert id == revision.id
    assert GTM.get_social_channel_idea(idea.id).status == "approved"
  end

  test "returns an error for an unknown revision" do
    assert {:error, "Social post revision not found."} =
             execute_tool(UpdateSocialPostRevision, conn_for(nil), %{
               "social_post_revision_id" => Ecto.UUID.generate(),
               "body" => "Draft"
             })
  end

  test "rejects an invalid status" do
    {:ok, idea} = GTM.create_social_channel_idea(%{"title" => "Invalid revision status"})
    {:ok, revision} = GTM.create_social_post_revision(idea, %{"body" => "Draft"})

    assert {:error, message} =
             execute_tool(UpdateSocialPostRevision, conn_for(nil), %{
               "social_post_revision_id" => revision.id,
               "status" => "queued"
             })

    assert message =~ "Could not update social post revision"
  end
end
