defmodule Atlas.MCP.Tools.ListBlogPostIdeas do
  @moduledoc """
  Lists blog post ideas in the GTM content backlog.
  """

  use Atlas.MCP.Tool,
    name: "list_blog_post_ideas",
    schema: %{
      "type" => "object",
      "properties" => %{}
    },
    output_schema:
      Atlas.MCP.Serializers.GTM.list_response_schema(
        :blog_post_ideas,
        Atlas.MCP.Serializers.GTM.blog_post_idea_schema()
      )

  alias Atlas.GTM
  alias Atlas.MCP.Serializers.GTM, as: GTMSerializer

  @impl EMCP.Tool
  def description, do: "List blog post ideas in the GTM content backlog, newest first."

  def execute(_conn, _args) do
    ideas =
      GTM.list_blog_post_ideas()
      |> Enum.map(&GTMSerializer.blog_post_idea/1)

    {:ok, GTMSerializer.list_response(:blog_post_ideas, ideas)}
  end
end
