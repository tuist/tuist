defmodule Atlas.MCP.Tools.CreateTimeOffLocation do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "create_time_off_location",
    schema: %{
      "type" => "object",
      "required" => ["name", "country_code"],
      "properties" => %{
        "name" => %{"type" => "string"},
        "country_code" => %{"type" => "string", "description" => "ISO 3166-1 alpha-2 code, e.g. DE."},
        "subdivision_code" => %{
          "type" => "string",
          "description" => "Optional ISO 3166-2 region, e.g. DE-BE. Omit for national holidays only."
        }
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
      "Create an immutable location calendar (administrator only). Import public holidays separately and add municipal dates where necessary."

  def execute(conn, args) do
    with :ok <- Tool.authorize_scope(conn, "admin:write", "Time off calendar management"),
         {:ok, location} <- TimeOff.create_location(args, Tool.current_user(conn), interface: "mcp") do
      {:ok, %{location: Serializer.location(location)}}
    else
      error -> Serializer.error(error)
    end
  end
end
