defmodule Atlas.MCP.Tools.CreateBlogPostIdeaComment do
  @moduledoc """
  Adds a follow-up comment to a blog post idea.
  """

  use Atlas.MCP.Tool,
    name: "create_blog_post_idea_comment",
    schema: %{
      "type" => "object",
      "required" => ["blog_post_idea_id", "body"],
      "properties" => %{
        "blog_post_idea_id" => %{"type" => "string"},
        "body" => %{"type" => "string", "description" => "Comment body."}
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "comment" => Atlas.MCP.Serializers.GTM.comment_schema()
      },
      "required" => ["comment"],
      "additionalProperties" => false
    }

  alias Atlas.GTM
  alias Atlas.MCP.Serializers.GTM, as: GTMSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "Add a follow-up comment to a blog post idea."

  def execute(conn, %{"blog_post_idea_id" => id} = args) do
    case GTM.get_blog_post_idea(id) do
      nil ->
        {:error, "Blog post idea not found."}

      idea ->
        attrs = Map.take(args, ["body"])

        case GTM.create_blog_post_idea_comment(idea, attrs, Tool.current_user(conn)) do
          {:ok, comment} ->
            {:ok, %{comment: GTMSerializer.comment(comment)}}

          {:error, changeset} ->
            {:error, "Could not create blog post idea comment: #{Tool.format_changeset_errors(changeset)}"}
        end
    end
  end
end
