defmodule Atlas.MCP.Tools.SyncPublicHolidays do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "sync_public_holidays",
    schema: %{"type" => "object", "properties" => %{}},
    output_schema:
      Atlas.MCP.Serializers.TimeOff.response_schema("location", Atlas.MCP.Serializers.TimeOff.location_schema())

  alias Atlas.MCP.Serializers.TimeOff, as: Serializer
  alias Atlas.MCP.Tool
  alias Atlas.TimeOff

  @impl EMCP.Tool
  def description,
    do:
      "Refresh the shared Berlin public holiday calendar from Nager.Date for the current and next year. Requires admin:write. Atlas also refreshes automatically at startup and daily. Provider failures preserve existing dates."

  def execute(conn, _args) do
    with :ok <- Tool.authorize_scope(conn, "admin:write", "Time off calendar management"),
         {:ok, location} <- TimeOff.sync_public_holidays(actor: Tool.current_user(conn), interface: "mcp") do
      {:ok, %{location: Serializer.location(location)}}
    else
      error -> Serializer.error(error)
    end
  end
end
