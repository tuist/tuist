defmodule Atlas.MCP.Tools.CreateBlogPostIdea do
  @moduledoc """
  Captures a new blog post idea in the GTM content backlog.
  """

  use Atlas.MCP.Tool,
    name: "create_blog_post_idea",
    schema: %{
      "type" => "object",
      "required" => ["title"],
      "properties" => %{
        "title" => %{"type" => "string", "description" => "Short, specific headline for the idea."},
        "description" => %{
          "type" => "string",
          "description" => "The angle, audience, and takeaway for the post."
        },
        "status" => %{"type" => "string", "enum" => ["idea", "in_progress", "published"]}
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "blog_post_idea" => Atlas.MCP.Serializers.GTM.blog_post_idea_schema()
      },
      "required" => ["blog_post_idea"],
      "additionalProperties" => false
    }

  alias Atlas.GTM
  alias Atlas.MCP.Serializers.GTM, as: GTMSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "Capture a blog post idea with a title and description in the GTM content backlog."

  def execute(conn, args) do
    attrs =
      args
      |> Map.take(["title", "description", "status"])
      |> Map.put("created_by_agent", "mcp")

    case GTM.create_blog_post_idea(attrs, Tool.current_user(conn), announce: true) do
      {:ok, idea} ->
        {:ok, %{blog_post_idea: GTMSerializer.blog_post_idea(idea)}}

      {:error, changeset} ->
        {:error, "Could not create blog post idea: #{Tool.format_changeset_errors(changeset)}"}
    end
  end
end
