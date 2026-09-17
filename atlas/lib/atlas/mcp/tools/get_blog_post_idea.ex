defmodule Atlas.MCP.Tools.GetBlogPostIdea do
  @moduledoc """
  Gets a blog post idea with its follow-up comments.
  """

  use Atlas.MCP.Tool,
    name: "get_blog_post_idea",
    schema: %{
      "type" => "object",
      "required" => ["blog_post_idea_id"],
      "properties" => %{
        "blog_post_idea_id" => %{"type" => "string"}
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "blog_post_idea" => Atlas.MCP.Serializers.GTM.blog_post_idea_with_comments_schema()
      },
      "required" => ["blog_post_idea"],
      "additionalProperties" => false
    }

  alias Atlas.GTM
  alias Atlas.MCP.Serializers.GTM, as: GTMSerializer

  @impl EMCP.Tool
  def description, do: "Get a blog post idea with its follow-up comments."

  def execute(_conn, %{"blog_post_idea_id" => id}) do
    case GTM.get_blog_post_idea(id) do
      nil ->
        {:error, "Blog post idea not found."}

      idea ->
        {:ok, %{blog_post_idea: GTMSerializer.blog_post_idea_with_comments(idea)}}
    end
  end
end
