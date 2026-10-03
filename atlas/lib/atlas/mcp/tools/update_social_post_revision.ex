defmodule Atlas.MCP.Tools.UpdateSocialPostRevision do
  @moduledoc """
  Updates a social post revision.
  """

  use Atlas.MCP.Tool,
    name: "update_social_post_revision",
    schema: %{
      "type" => "object",
      "required" => ["social_post_revision_id"],
      "properties" => %{
        "social_post_revision_id" => %{"type" => "string"},
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
  def description, do: "Update a social post revision, including marking it as approved."

  def execute(conn, %{"social_post_revision_id" => id} = args) do
    case GTM.get_social_post_revision(id) do
      nil ->
        {:error, "Social post revision not found."}

      revision ->
        attrs = Map.take(args, ["body", "notes", "status"])

        case GTM.update_social_post_revision(revision, attrs, actor: Tool.current_user(conn)) do
          {:ok, updated} ->
            {:ok, %{social_post_revision: GTMSerializer.social_post_revision(updated)}}

          {:error, changeset} ->
            {:error, "Could not update social post revision: #{Tool.format_changeset_errors(changeset)}"}
        end
    end
  end
end
