defmodule Atlas.MCP.Tools.ImportPublicHolidays do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "import_public_holidays",
    schema: %{
      "type" => "object",
      "required" => ["location_id", "year"],
      "properties" => %{
        "location_id" => %{"type" => "string"},
        "year" => %{"type" => "integer", "minimum" => 2000, "maximum" => 2100}
      }
    },
    output_schema:
      Atlas.MCP.Serializers.TimeOff.response_schema("location", Atlas.MCP.Serializers.TimeOff.location_schema())

  alias Atlas.MCP.Serializers.TimeOff, as: Serializer
  alias Atlas.MCP.Tool
  alias Atlas.TimeOff

  @impl EMCP.Tool
  def description,
    do:
      "Import one year of national and matching regional public holidays from Nager.Date (administrator only). Replaces imported dates for that year, preserving manual dates. Review municipal coverage. Failure preserves the existing calendar."

  def execute(conn, %{"location_id" => location_id, "year" => year}) do
    with :ok <- Tool.authorize_scope(conn, "admin:write", "Time off calendar management"),
         {:ok, location} <- TimeOff.import_holidays(location_id, year, Tool.current_user(conn), interface: "mcp") do
      {:ok, %{location: Serializer.location(location)}}
    else
      error -> Serializer.error(error)
    end
  end
end
