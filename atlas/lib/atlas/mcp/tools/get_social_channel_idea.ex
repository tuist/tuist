defmodule Atlas.MCP.Tools.GetSocialChannelIdea do
  @moduledoc """
  Gets a social-channel idea.
  """

  use Atlas.MCP.Tool,
    name: "get_social_channel_idea",
    schema: %{
      "type" => "object",
      "required" => ["social_channel_idea_id"],
      "properties" => %{
        "social_channel_idea_id" => %{"type" => "string"}
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "social_channel_idea" => Atlas.MCP.Serializers.GTM.social_channel_idea_with_post_revisions_schema()
      },
      "required" => ["social_channel_idea"],
      "additionalProperties" => false
    }

  alias Atlas.GTM
  alias Atlas.MCP.Serializers.GTM, as: GTMSerializer

  @impl EMCP.Tool
  def description, do: "Get a social-channel idea."

  def execute(_conn, %{"social_channel_idea_id" => id}) do
    case GTM.get_social_channel_idea(id) do
      nil ->
        {:error, "Social-channel idea not found."}

      idea ->
        {:ok, %{social_channel_idea: GTMSerializer.social_channel_idea_with_post_revisions(idea)}}
    end
  end
end
