defmodule Atlas.MCP.Tools.GetSocialPostRevision do
  @moduledoc """
  Gets a social post revision.
  """

  use Atlas.MCP.Tool,
    name: "get_social_post_revision",
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
        "social_post_revision" => Atlas.MCP.Serializers.GTM.social_post_revision_schema()
      },
      "required" => ["social_post_revision"],
      "additionalProperties" => false
    }

  alias Atlas.GTM
  alias Atlas.MCP.Serializers.GTM, as: GTMSerializer

  @impl EMCP.Tool
  def description, do: "Get a social post revision."

  def execute(_conn, %{"social_post_revision_id" => id}) do
    case GTM.get_social_post_revision(id) do
      nil ->
        {:error, "Social post revision not found."}

      revision ->
        {:ok, %{social_post_revision: GTMSerializer.social_post_revision(revision)}}
    end
  end
end
