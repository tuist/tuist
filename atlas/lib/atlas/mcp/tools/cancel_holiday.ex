defmodule Atlas.MCP.Tools.CancelHoliday do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "cancel_holiday",
    schema: %{"type" => "object", "required" => ["id"], "properties" => %{"id" => %{"type" => "string"}}},
    output_schema:
      Atlas.MCP.Serializers.TimeOff.response_schema("booking", Atlas.MCP.Serializers.TimeOff.booking_schema())

  alias Atlas.MCP.Serializers.TimeOff, as: Serializer
  alias Atlas.MCP.Tool
  alias Atlas.TimeOff

  @impl EMCP.Tool
  def description, do: "Cancel a holiday reported by the caller. Does not allow cancelling another person's holiday."

  def execute(conn, %{"id" => id}) do
    with :ok <- Tool.authorize_authenticated(conn),
         {:ok, booking} <- TimeOff.cancel_holiday(id, Tool.current_user(conn), interface: "mcp") do
      {:ok, %{booking: Serializer.booking(booking)}}
    else
      error -> Serializer.error(error)
    end
  end
end
