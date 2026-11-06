defmodule Atlas.MCP.Tools.AddPublicHoliday do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "add_public_holiday",
    schema: %{
      "type" => "object",
      "required" => ["location_id", "name", "date"],
      "properties" => %{
        "location_id" => %{"type" => "string"},
        "name" => %{"type" => "string"},
        "date" => %{"type" => "string", "format" => "date"}
      }
    },
    output_schema:
      Atlas.MCP.Serializers.TimeOff.response_schema("holiday", Atlas.MCP.Serializers.TimeOff.holiday_schema())

  alias Atlas.MCP.Serializers.TimeOff, as: Serializer
  alias Atlas.MCP.Tool
  alias Atlas.TimeOff

  @impl EMCP.Tool
  def description,
    do:
      "Add a local or municipal public holiday to a location calendar (administrator only). Manual dates survive public holiday reimports."

  def execute(conn, %{"location_id" => location_id} = args) do
    with :ok <- Tool.authorize_scope(conn, "admin:write", "Time off calendar management"),
         {:ok, holiday} <- TimeOff.add_holiday(location_id, args, Tool.current_user(conn), interface: "mcp") do
      {:ok, %{holiday: Serializer.holiday(holiday)}}
    else
      error -> Serializer.error(error)
    end
  end
end
