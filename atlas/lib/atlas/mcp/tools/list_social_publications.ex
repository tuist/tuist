defmodule Atlas.MCP.Tools.ListSocialPublications do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "list_social_publications",
    schema: %{
      "type" => "object",
      "properties" => %{
        "status" => %{"type" => "string", "enum" => Atlas.GTM.SocialPublication.statuses()},
        "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "required" => ["publications"],
      "properties" => %{
        "publications" => %{"type" => "array", "items" => Atlas.MCP.Serializers.SocialPublishing.publication_schema()}
      },
      "additionalProperties" => false
    }

  alias Atlas.GTM.SocialPublishing
  alias Atlas.MCP.Serializers.SocialPublishing, as: Serializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description,
    do:
      "List posts and threads drafted, approved, scheduled or published to the X accounts Atlas holds, newest scheduled first, with who approved them and the published post's URL. Requires gtm:read."

  def execute(conn, args) do
    with :ok <- Tool.authorize_scope(conn, "gtm:read", "Social publishing") do
      publications = SocialPublishing.list(status: args["status"], limit: args["limit"] || 50)
      {:ok, %{publications: Enum.map(publications, &Serializer.publication/1)}}
    end
  end
end
