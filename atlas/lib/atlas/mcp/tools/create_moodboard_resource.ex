defmodule Atlas.MCP.Tools.CreateMoodboardResource do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "create_moodboard_resource",
    schema: %{
      "type" => "object",
      "properties" =>
        Map.put(Atlas.MCP.Serializers.Moodboard.attributes(), "request_id", %{"type" => "string", "format" => "uuid"}),
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
      "Save a link, article, design reference or original text to the team's Moodboard. Supply a URL or content. Optional request_id is an actor-scoped replay UUID; retry uncertain saves with the same UUID and exact fields. Link previews and embeddings are discovered in the background; description is a reviewed note, not fetched text."

  def execute(conn, args) do
    with :ok <- Tool.authorize_authenticated(conn, "Moodboard tools"),
         {:ok, resource} <-
           create(args, Tool.current_user(conn), interface: Tool.audit_interface(conn)) do
      {:ok, %{resource: Serializer.resource(resource)}}
    else
      {:error, message} when is_binary(message) -> {:error, message}
      {:error, reason} -> {:error, Serializer.error(reason)}
    end
  end

  defp create(%{"request_id" => id} = args, user, opts),
    do: Moodboard.capture_resource(id, Map.delete(args, "request_id"), user, opts)

  defp create(args, user, opts), do: Moodboard.create_resource(args, user, opts)
end
