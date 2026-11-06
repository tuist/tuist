defmodule Atlas.MCP.Tools.RemovePublicHoliday do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "remove_public_holiday",
    schema: %{"type" => "object", "required" => ["id"], "properties" => %{"id" => %{"type" => "string"}}},
    output_schema:
      Atlas.MCP.Serializers.TimeOff.response_schema("holiday", Atlas.MCP.Serializers.TimeOff.holiday_schema())

  alias Atlas.MCP.Serializers.TimeOff, as: Serializer
  alias Atlas.MCP.Tool
  alias Atlas.TimeOff

  @impl EMCP.Tool
  def description,
    do:
      "Remove a public holiday (administrator only). Imported dates can return on reimport. Leave-day counts reflect the configured calendar."

  def execute(conn, %{"id" => id}) do
    with :ok <- Tool.authorize_scope(conn, "admin:write", "Time off calendar management"),
         {:ok, holiday} <- TimeOff.remove_holiday(id, Tool.current_user(conn), interface: "mcp") do
      {:ok, %{holiday: Serializer.holiday(holiday)}}
    else
      error -> Serializer.error(error)
    end
  end
end
