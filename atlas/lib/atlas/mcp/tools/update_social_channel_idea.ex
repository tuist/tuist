defmodule Atlas.MCP.Tools.UpdateSocialChannelIdea do
  @moduledoc """
  Updates a social-channel idea in the go-to-market content backlog.
  """

  use Atlas.MCP.Tool,
    name: "update_social_channel_idea",
    schema: %{
      "type" => "object",
      "required" => ["social_channel_idea_id"],
      "properties" => %{
        "social_channel_idea_id" => %{"type" => "string"},
        "title" => %{"type" => "string", "description" => "Short, specific headline for the idea."},
        "description" => %{
          "type" => "string",
          "description" => "The angle, source material, and desired takeaway."
        },
        "status" => %{"type" => "string", "enum" => ["idea", "approved"]}
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "social_channel_idea" => Atlas.MCP.Serializers.GTM.social_channel_idea_schema()
      },
      "required" => ["social_channel_idea"],
      "additionalProperties" => false
    }

  alias Atlas.GTM
  alias Atlas.MCP.Serializers.GTM, as: GTMSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "Update a social-channel idea."

  def execute(conn, %{"social_channel_idea_id" => id} = args) do
    case GTM.get_social_channel_idea(id) do
      nil ->
        {:error, "Social-channel idea not found."}

      idea ->
        attrs = Map.take(args, ["title", "description", "status"])

        case GTM.update_social_channel_idea(idea, attrs, actor: Tool.current_user(conn)) do
          {:ok, updated} ->
            {:ok, %{social_channel_idea: GTMSerializer.social_channel_idea(updated)}}

          {:error, changeset} ->
            {:error, "Could not update social-channel idea: #{Tool.format_changeset_errors(changeset)}"}
        end
    end
  end
end
