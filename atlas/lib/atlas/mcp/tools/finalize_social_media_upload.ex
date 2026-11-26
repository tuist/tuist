defmodule Atlas.MCP.Tools.FinalizeSocialMediaUpload do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "finalize_social_media_upload",
    schema: %{
      "type" => "object",
      "required" => ["media_id"],
      "properties" => %{"media_id" => %{"type" => "string"}},
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "required" => ["media_id", "byte_size"],
      "properties" => %{"media_id" => %{"type" => "string"}, "byte_size" => %{"type" => "integer"}},
      "additionalProperties" => false
    }

  alias Atlas.GTM.SocialPublishing
  alias Atlas.MCP.Serializers.SocialPublishing, as: Serializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description,
    do:
      "Confirm that the bytes for a `create_social_media_upload` reservation arrived and are within X's limits, so the media can be attached to a post. Requires gtm:write."

  def execute(conn, %{"media_id" => id}) do
    with :ok <- Tool.authorize_scope(conn, "gtm:write", "Social publishing") do
      case SocialPublishing.finalize_media(Tool.current_user(conn), id) do
        {:ok, media} -> {:ok, %{media_id: media.id, byte_size: media.byte_size}}
        {:error, reason} -> Serializer.error(reason)
      end
    end
  end
end
