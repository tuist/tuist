defmodule Atlas.MCP.Tools.CreateBlogPostIdeaTest do
  use Atlas.MCP.ToolCase

  alias Atlas.GTM
  alias Atlas.MCP.Tools.CreateBlogPostIdea

  test "captures a blog post idea attributed to the current user" do
    user = insert_user!(%{name: "Casey Writer"})

    {:ok, payload} =
      execute_tool(CreateBlogPostIdea, conn_for(user), %{
        "title" => "How Tuist speeds up CI",
        "description" => "Benchmarks and migration tips."
      })

    assert %{blog_post_idea: %{id: id, title: "How Tuist speeds up CI", status: "idea"}} = payload
    assert is_binary(id)

    idea = GTM.get_blog_post_idea(id)
    assert idea.created_by_agent == "mcp"
    assert idea.author_id == user.id
  end

  test "accepts an explicit status" do
    {:ok, payload} =
      execute_tool(CreateBlogPostIdea, conn_for(nil), %{
        "title" => "Already shipping",
        "status" => "in_progress"
      })

    assert %{blog_post_idea: %{status: "in_progress"}} = payload
  end

  test "rejects a blank title" do
    assert {:error, message} = execute_tool(CreateBlogPostIdea, conn_for(nil), %{"title" => "   "})
    assert message =~ "Could not create blog post idea"
  end
end
