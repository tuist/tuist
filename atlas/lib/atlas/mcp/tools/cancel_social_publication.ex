defmodule Atlas.MCP.Tools.CancelSocialPublication do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "cancel_social_publication",
    schema: %{
      "type" => "object",
      "required" => ["id"],
      "properties" => %{"id" => %{"type" => "string"}},
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "required" => ["publication"],
      "properties" => %{"publication" => Atlas.MCP.Serializers.SocialPublishing.publication_schema()},
      "additionalProperties" => false
    }

  alias Atlas.GTM.SocialPublishing
  alias Atlas.MCP.Serializers.SocialPublishing, as: Serializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description,
    do:
      "Cancel a draft, approved or failed publication so it never publishes. Published posts stay on X. Requires gtm:write."

  def execute(conn, %{"id" => id}) do
    with :ok <- Tool.authorize_scope(conn, "gtm:write", "Social publishing") do
      case SocialPublishing.cancel(Tool.current_user(conn), id) do
        {:ok, publication} -> {:ok, %{publication: Serializer.publication(SocialPublishing.get(publication.id))}}
        {:error, reason} -> Serializer.error(reason)
      end
    end
  end
end
