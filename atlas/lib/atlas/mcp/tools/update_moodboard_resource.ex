defmodule Atlas.MCP.Tools.UpdateMoodboardResource do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "update_moodboard_resource",
    schema: %{
      "type" => "object",
      "properties" => Map.put(Atlas.MCP.Serializers.Moodboard.attributes(), "resource_id", %{"type" => "string"}),
      "required" => ["resource_id"],
      "additionalProperties" => false
    },
    output_schema: Atlas.MCP.Serializers.Moodboard.response_schema()

  alias Atlas.MCP.Serializers.Moodboard, as: Serializer
  alias Atlas.MCP.Tool
  alias Atlas.Moodboard

  @impl EMCP.Tool
  def description,
    do: "Edit a Moodboard resource you contributed. Omitted fields are preserved; use null to clear optional fields."

  def execute(conn, args) do
    with :ok <- Tool.authorize_authenticated(conn, "Moodboard tools"),
         {:ok, resource} <-
           Moodboard.update_resource(args["resource_id"], Map.delete(args, "resource_id"), Tool.current_user(conn),
             interface: Tool.audit_interface(conn)
           ) do
      {:ok, %{resource: Serializer.resource(resource)}}
    else
      {:error, message} when is_binary(message) -> {:error, message}
      {:error, reason} -> {:error, Serializer.error(reason)}
    end
  end
end
