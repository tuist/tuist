defmodule Atlas.MCP.Tools.CreateSocialPostRevision do
  @moduledoc """
  Adds a post revision to a social-channel idea.
  """

  use Atlas.MCP.Tool,
    name: "create_social_post_revision",
    schema: %{
      "type" => "object",
      "required" => ["social_channel_idea_id", "body"],
      "properties" => %{
        "social_channel_idea_id" => %{"type" => "string"},
        "body" => %{"type" => "string", "description" => "The draft social post text."},
        "notes" => %{"type" => "string", "description" => "Optional note about this revision."},
        "status" => %{"type" => "string", "enum" => ["draft", "approved"]}
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "social_post_revision" => Atlas.MCP.Serializers.GTM.social_post_revision_schema()
      },
      "required" => ["social_post_revision"],
      "additionalProperties" => false
    }

  alias Atlas.GTM
  alias Atlas.MCP.Serializers.GTM, as: GTMSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "Add a draft or approved post revision to a social-channel idea."

  def execute(conn, %{"social_channel_idea_id" => id} = args) do
    case GTM.get_social_channel_idea(id) do
      nil ->
        {:error, "Social-channel idea not found."}

      idea ->
        attrs =
          args
          |> Map.take(["body", "notes", "status"])
          |> Map.put("created_by_agent", "mcp")

        case GTM.create_social_post_revision(idea, attrs, Tool.current_user(conn), actor: Tool.current_user(conn)) do
          {:ok, revision} ->
            {:ok, %{social_post_revision: GTMSerializer.social_post_revision(revision)}}

          {:error, changeset} ->
            {:error, "Could not create social post revision: #{Tool.format_changeset_errors(changeset)}"}
        end
    end
  end
end
