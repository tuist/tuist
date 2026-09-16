defmodule Atlas.MCP.Tools.CreateBlogPostIdeaCommentTest do
  use Atlas.MCP.ToolCase

  alias Atlas.GTM
  alias Atlas.MCP.Tools.CreateBlogPostIdeaComment

  test "adds a comment attributed to the current user" do
    user = insert_user!(%{name: "Casey Reviewer"})
    {:ok, idea} = GTM.create_blog_post_idea(%{"title" => "Needs a follow-up"})

    {:ok, payload} =
      execute_tool(CreateBlogPostIdeaComment, conn_for(user), %{
        "blog_post_idea_id" => idea.id,
        "body" => "Pair this with the cache benchmarks."
      })

    assert %{comment: %{id: id, body: "Pair this with the cache benchmarks."}} = payload
    assert is_binary(id)

    idea = GTM.get_blog_post_idea(idea.id)
    assert [%{author: %{name: "Casey Reviewer"}}] = idea.comments
  end

  test "rejects an empty comment" do
    {:ok, idea} = GTM.create_blog_post_idea(%{"title" => "Has thread"})

    assert {:error, _message} =
             execute_tool(CreateBlogPostIdeaComment, conn_for(nil), %{
               "blog_post_idea_id" => idea.id,
               "body" => "  "
             })
  end

  test "returns an error for an unknown idea" do
    assert {:error, "Blog post idea not found."} =
             execute_tool(CreateBlogPostIdeaComment, conn_for(nil), %{
               "blog_post_idea_id" => Ecto.UUID.generate(),
               "body" => "Lost comment"
             })
  end
end
