defmodule Atlas.MCP.Tools.CreateSocialPostRevisionTest do
  use Atlas.MCP.ToolCase

  alias Atlas.GTM
  alias Atlas.MCP.Tools.CreateSocialPostRevision

  test "adds a post revision to a social-channel idea" do
    user = insert_user!(%{name: "Casey Social"})
    {:ok, idea} = GTM.create_social_channel_idea(%{"title" => "Social draft"})

    {:ok, payload} =
      execute_tool(CreateSocialPostRevision, conn_for(user), %{
        "social_channel_idea_id" => idea.id,
        "body" => "Draft the post around saved review time.",
        "notes" => "First protocol pass."
      })

    assert %{
             social_post_revision: %{
               id: id,
               social_channel_idea_id: idea_id,
               revision_number: 1,
               body: "Draft the post around saved review time.",
               status: "draft"
             }
           } = payload

    assert is_binary(id)
    assert idea_id == idea.id

    revision = GTM.get_social_post_revision(id)
    assert revision.author_id == user.id
    assert revision.created_by_agent == "mcp"
  end

  test "can create an approved revision" do
    {:ok, idea} = GTM.create_social_channel_idea(%{"title" => "Publish immediately"})

    {:ok, payload} =
      execute_tool(CreateSocialPostRevision, conn_for(nil), %{
        "social_channel_idea_id" => idea.id,
        "body" => "Published post.",
        "status" => "approved"
      })

    assert %{social_post_revision: %{status: "approved"}} = payload
    assert GTM.get_social_channel_idea(idea.id).status == "approved"
  end

  test "returns an error for an unknown idea" do
    assert {:error, "Social-channel idea not found."} =
             execute_tool(CreateSocialPostRevision, conn_for(nil), %{
               "social_channel_idea_id" => Ecto.UUID.generate(),
               "body" => "Draft"
             })
  end
end
