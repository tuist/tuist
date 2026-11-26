defmodule Atlas.MCP.Tools.CreateSocialMediaUpload do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "create_social_media_upload",
    schema: %{
      "type" => "object",
      "required" => ["filename", "content_type"],
      "properties" => %{
        "filename" => %{"type" => "string", "maxLength" => 255},
        "content_type" => %{"type" => "string", "enum" => Atlas.GTM.SocialMedia.content_types()}
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "required" => ["media_id", "upload_url", "upload_method", "upload_expires_at", "required_headers"],
      "properties" => %{
        "media_id" => %{"type" => "string"},
        "upload_url" => %{"type" => "string"},
        "upload_method" => %{"type" => "string"},
        "upload_expires_at" => %{"type" => "string"},
        "required_headers" => %{"type" => "object", "additionalProperties" => %{"type" => "string"}}
      },
      "additionalProperties" => false
    }

  alias Atlas.GTM.SocialPublishing
  alias Atlas.MCP.Serializers.SocialPublishing, as: Serializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description,
    do:
      "Reserve an image (JPEG, PNG, WebP, up to 5 MB), GIF (15 MB) or video (MP4 or MOV, 100 MB) for a social post and return a presigned PUT URL. PUT the bytes with the `Content-Type` from `required_headers`, call `finalize_social_media_upload`, then pass `media_id` in a post's `media_ids` to `save_social_publication`. Requires gtm:write."

  def execute(conn, args) do
    with :ok <- Tool.authorize_scope(conn, "gtm:write", "Social publishing") do
      case SocialPublishing.create_media_upload(Tool.current_user(conn), args["filename"], args["content_type"]) do
        {:ok, upload} ->
          {:ok,
           %{
             media_id: upload.media.id,
             upload_url: upload.upload_url,
             upload_method: "PUT",
             upload_expires_at: Tool.iso8601(upload.upload_expires_at),
             required_headers: upload.required_headers
           }}

        {:error, reason} ->
          Serializer.error(reason)
      end
    end
  end
end
