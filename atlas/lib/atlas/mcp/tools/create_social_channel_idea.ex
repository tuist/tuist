defmodule Atlas.MCP.Tools.CreateSocialChannelIdea do
  @moduledoc """
  Captures a new social-channel idea in the go-to-market content backlog.
  """

  use Atlas.MCP.Tool,
    name: "create_social_channel_idea",
    schema: %{
      "type" => "object",
      "required" => ["title"],
      "properties" => %{
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
  def description do
    "Capture a social-channel idea with a title, optional description, and status."
  end

  def execute(conn, args) do
    attrs =
      args
      |> Map.take(["title", "description", "status"])
      |> Map.put("created_by_agent", "mcp")

    case GTM.create_social_channel_idea(attrs, Tool.current_user(conn)) do
      {:ok, idea} ->
        {:ok, %{social_channel_idea: GTMSerializer.social_channel_idea(idea)}}

      {:error, changeset} ->
        {:error, "Could not create social-channel idea: #{Tool.format_changeset_errors(changeset)}"}
    end
  end
end
