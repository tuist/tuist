defmodule Atlas.MCP.Tools.ListBlogPostIdeasTest do
  use Atlas.MCP.ToolCase

  alias Atlas.GTM
  alias Atlas.MCP.Tools.ListBlogPostIdeas

  test "lists ideas with a count" do
    {:ok, _} = GTM.create_blog_post_idea(%{"title" => "First idea"})
    {:ok, _} = GTM.create_blog_post_idea(%{"title" => "Second idea", "status" => "published"})

    {:ok, payload} = execute_tool(ListBlogPostIdeas, conn_for(nil), %{})

    assert %{blog_post_ideas: ideas, count: 2} = payload
    assert "First idea" in Enum.map(ideas, & &1.title)
    assert "Second idea" in Enum.map(ideas, & &1.title)
  end

  test "returns an empty list when there are no ideas" do
    assert {:ok, %{blog_post_ideas: [], count: 0}} = execute_tool(ListBlogPostIdeas, conn_for(nil), %{})
  end
end
