defmodule Atlas.MCP.Tools.DeleteSocialPostRevision do
  @moduledoc """
  Deletes a social post revision.
  """

  use Atlas.MCP.Tool,
    name: "delete_social_post_revision",
    schema: %{
      "type" => "object",
      "required" => ["social_post_revision_id"],
      "properties" => %{
        "social_post_revision_id" => %{"type" => "string"}
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "deleted" => %{"type" => "boolean"},
        "social_post_revision" => Atlas.MCP.Serializers.GTM.social_post_revision_schema()
      },
      "required" => ["deleted", "social_post_revision"],
      "additionalProperties" => false
    }

  alias Atlas.GTM
  alias Atlas.MCP.Serializers.GTM, as: GTMSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "Delete a social post revision."

  def execute(conn, %{"social_post_revision_id" => id}) do
    case GTM.get_social_post_revision(id) do
      nil ->
        {:error, "Social post revision not found."}

      revision ->
        case GTM.delete_social_post_revision(revision, actor: Tool.current_user(conn)) do
          {:ok, deleted} ->
            {:ok, %{deleted: true, social_post_revision: GTMSerializer.social_post_revision(deleted)}}

          {:error, changeset} ->
            {:error, "Could not delete social post revision: #{Tool.format_changeset_errors(changeset)}"}
        end
    end
  end
end
