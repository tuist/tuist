defmodule Atlas.MCP.Tools.DeleteMoodboardResource do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "delete_moodboard_resource",
    schema: %{
      "type" => "object",
      "properties" => %{"resource_id" => %{"type" => "string"}},
      "required" => ["resource_id"],
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"deleted" => %{"type" => "boolean"}},
      "required" => ["deleted"],
      "additionalProperties" => false
    }

  alias Atlas.MCP.Serializers.Moodboard, as: Serializer
  alias Atlas.MCP.Tool
  alias Atlas.Moodboard

  @impl EMCP.Tool
  def description, do: "Permanently remove a Moodboard resource you contributed."

  def execute(conn, args) do
    with :ok <- Tool.authorize_authenticated(conn, "Moodboard tools"),
         {:ok, _resource} <-
           Moodboard.delete_resource(args["resource_id"], Tool.current_user(conn),
             interface: Tool.audit_interface(conn)
           ) do
      {:ok, %{deleted: true}}
    else
      {:error, message} when is_binary(message) -> {:error, message}
      {:error, reason} -> {:error, Serializer.error(reason)}
    end
  end
end
