defmodule Atlas.MCP.Tools.GetBlogPostIdeaTest do
  use Atlas.MCP.ToolCase

  alias Atlas.GTM
  alias Atlas.MCP.Tools.GetBlogPostIdea

  test "returns an idea with its comments" do
    {:ok, idea} = GTM.create_blog_post_idea(%{"title" => "Deep dive"})
    {:ok, _} = GTM.create_blog_post_idea_comment(idea, %{"body" => "Add a diagram."})

    {:ok, payload} =
      execute_tool(GetBlogPostIdea, conn_for(nil), %{"blog_post_idea_id" => idea.id})

    assert %{blog_post_idea: %{id: id, title: "Deep dive", comments: [%{body: "Add a diagram."}]}} = payload
    assert id == idea.id
  end

  test "returns an error for an unknown idea" do
    assert {:error, "Blog post idea not found."} =
             execute_tool(GetBlogPostIdea, conn_for(nil), %{"blog_post_idea_id" => Ecto.UUID.generate()})
  end
end
