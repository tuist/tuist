defmodule Atlas.MCP.Tools.GetEmailAudience do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "get_email_audience",
    schema: %{
      "type" => "object",
      "required" => ["audience_id"],
      "properties" => %{"audience_id" => %{"type" => "string"}}
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"audience" => Atlas.MCP.Serializers.GTMEmail.audience_with_members_schema()},
      "required" => ["audience"],
      "additionalProperties" => false
    }

  alias Atlas.GTM
  alias Atlas.MCP.Serializers.GTMEmail

  @impl EMCP.Tool
  def description,
    do:
      "Get an Atlas email audience with its current memberships and broadcast history. Dynamic audiences resolve matching account contacts when read."

  def execute(_conn, %{"audience_id" => id}) do
    case GTM.get_email_audience(id) do
      nil -> {:error, "Email audience not found."}
      audience -> {:ok, %{audience: GTMEmail.audience_with_members(audience)}}
    end
  end
end
