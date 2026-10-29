defmodule Atlas.MCP.Tools.AssignTimeOffLocation do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "assign_time_off_location",
    schema: %{
      "type" => "object",
      "required" => ["user_id", "location_id"],
      "properties" => %{"user_id" => %{"type" => "string"}, "location_id" => %{"type" => "string"}}
    },
    output_schema:
      Atlas.MCP.Serializers.TimeOff.object(%{
        "user_id" => %{"type" => "string"},
        "location_id" => %{"type" => "string"}
      })

  alias Atlas.MCP.Serializers.TimeOff, as: Serializer
  alias Atlas.MCP.Tool
  alias Atlas.TimeOff

  @impl EMCP.Tool
  def description,
    do:
      "Assign an Atlas user's public holiday location (administrator only). Affects new bookings, not the location snapshotted on existing leave."

  def execute(conn, %{"user_id" => user_id, "location_id" => location_id}) do
    with :ok <- Tool.authorize_scope(conn, "admin:write", "Time off calendar management"),
         {:ok, user} <- TimeOff.assign_location(user_id, location_id, Tool.current_user(conn), interface: "mcp") do
      {:ok, %{user_id: user.id, location_id: user.time_off_location_id}}
    else
      error -> Serializer.error(error)
    end
  end
end
