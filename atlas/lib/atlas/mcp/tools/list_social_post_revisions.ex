defmodule Atlas.MCP.Tools.ListSocialPostRevisions do
  @moduledoc """
  Lists post revisions for a social-channel idea.
  """

  use Atlas.MCP.Tool,
    name: "list_social_post_revisions",
    schema: %{
      "type" => "object",
      "required" => ["social_channel_idea_id"],
      "properties" => %{
        "social_channel_idea_id" => %{"type" => "string"}
      }
    },
    output_schema:
      Atlas.MCP.Serializers.GTM.list_response_schema(
        :social_post_revisions,
        Atlas.MCP.Serializers.GTM.social_post_revision_schema()
      )

  alias Atlas.GTM
  alias Atlas.MCP.Serializers.GTM, as: GTMSerializer

  @impl EMCP.Tool
  def description, do: "List post revisions for a social-channel idea."

  def execute(_conn, %{"social_channel_idea_id" => id}) do
    case GTM.get_social_channel_idea(id) do
      nil ->
        {:error, "Social-channel idea not found."}

      idea ->
        revisions =
          idea
          |> GTM.list_social_post_revisions()
          |> Enum.map(&GTMSerializer.social_post_revision/1)

        {:ok, GTMSerializer.list_response(:social_post_revisions, revisions)}
    end
  end
end
