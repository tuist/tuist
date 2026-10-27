defmodule Atlas.MCP.Tools.CreateMoodboardResource do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "create_moodboard_resource",
    schema: %{
      "type" => "object",
      "properties" => Atlas.MCP.Serializers.Moodboard.attributes(),
      "required" => ["title"],
      "additionalProperties" => false
    },
    output_schema: Atlas.MCP.Serializers.Moodboard.response_schema()

  alias Atlas.MCP.Serializers.Moodboard, as: Serializer
  alias Atlas.MCP.Tool
  alias Atlas.Moodboard

  @impl EMCP.Tool
  def description,
    do:
      "Save a link, article, design reference or original text to the team's Moodboard. Supply a URL or content. Link previews and embeddings are discovered in the background; description is the contributor's personal note, not fetched text."

  def execute(conn, args) do
    with :ok <- Tool.authorize_authenticated(conn, "Moodboard tools"),
         {:ok, resource} <-
           Moodboard.create_resource(args, Tool.current_user(conn), interface: Tool.audit_interface(conn)) do
      {:ok, %{resource: Serializer.resource(resource)}}
    else
      {:error, message} when is_binary(message) -> {:error, message}
      {:error, reason} -> {:error, Serializer.error(reason)}
    end
  end
end
