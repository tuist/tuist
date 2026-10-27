defmodule Atlas.MCP.Tools.ListSocialChannelIdeas do
  @moduledoc """
  Lists social-channel ideas in the go-to-market content backlog.
  """

  use Atlas.MCP.Tool,
    name: "list_social_channel_ideas",
    schema: %{
      "type" => "object",
      "properties" => %{}
    },
    output_schema:
      Atlas.MCP.Serializers.GTM.list_response_schema(
        :social_channel_ideas,
        Atlas.MCP.Serializers.GTM.social_channel_idea_schema()
      )

  alias Atlas.GTM
  alias Atlas.MCP.Serializers.GTM, as: GTMSerializer

  @impl EMCP.Tool
  def description, do: "List social-channel ideas in the go-to-market content backlog, newest first."

  def execute(_conn, _args) do
    ideas =
      GTM.list_social_channel_ideas()
      |> Enum.map(&GTMSerializer.social_channel_idea/1)

    {:ok, GTMSerializer.list_response(:social_channel_ideas, ideas)}
  end
end
