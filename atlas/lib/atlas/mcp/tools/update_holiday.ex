defmodule Atlas.MCP.Tools.UpdateHoliday do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "update_holiday",
    schema: %{
      "type" => "object",
      "required" => ["id"],
      "properties" => %{
        "id" => %{"type" => "string"},
        "starts_on" => %{"type" => "string", "format" => "date"},
        "ends_on" => %{"type" => "string", "format" => "date"}
      }
    },
    output_schema:
      Atlas.MCP.Serializers.TimeOff.response_schema("booking", Atlas.MCP.Serializers.TimeOff.booking_schema())

  alias Atlas.MCP.Serializers.TimeOff, as: Serializer
  alias Atlas.MCP.Tool
  alias Atlas.TimeOff

  @impl EMCP.Tool
  def description,
    do:
      "Change the dates of the caller's own holiday request. Changed dates require fresh approval and clear the previous reviewer. Rejected requests can be resubmitted; cancelled requests cannot be changed. The original location calendar is preserved. Saving unchanged approved dates preserves approval."

  def execute(conn, %{"id" => id} = args) do
    with :ok <- Tool.authorize_authenticated(conn),
         {:ok, booking} <-
           TimeOff.update_holiday(id, Map.take(args, ["starts_on", "ends_on"]), Tool.current_user(conn),
             interface: "mcp"
           ) do
      {:ok, %{booking: Serializer.booking(booking)}}
    else
      error -> Serializer.error(error)
    end
  end
end
