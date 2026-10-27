defmodule Atlas.MCP.Tools.DeleteSocialChannelIdea do
  @moduledoc """
  Deletes a social-channel idea from the go-to-market content backlog.
  """

  use Atlas.MCP.Tool,
    name: "delete_social_channel_idea",
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
        "deleted" => %{"type" => "boolean"},
        "social_channel_idea" => Atlas.MCP.Serializers.GTM.social_channel_idea_schema()
      },
      "required" => ["deleted", "social_channel_idea"],
      "additionalProperties" => false
    }

  alias Atlas.GTM
  alias Atlas.MCP.Serializers.GTM, as: GTMSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "Delete a social-channel idea."

  def execute(conn, %{"social_channel_idea_id" => id}) do
    case GTM.get_social_channel_idea(id) do
      nil ->
        {:error, "Social-channel idea not found."}

      idea ->
        case GTM.delete_social_channel_idea(idea, actor: Tool.current_user(conn)) do
          {:ok, deleted} ->
            {:ok, %{deleted: true, social_channel_idea: GTMSerializer.social_channel_idea(deleted)}}

          {:error, changeset} ->
            {:error, "Could not delete social-channel idea: #{Tool.format_changeset_errors(changeset)}"}
        end
    end
  end
end
