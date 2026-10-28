defmodule Atlas.MCP.Tools.ReportHoliday do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "report_holiday",
    schema: %{
      "type" => "object",
      "required" => ["starts_on", "ends_on"],
      "properties" => %{
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
      "Request the caller's full-day holiday (inclusive dates). Starts pending until another user with time_off_approvals:write approves or rejects it. Requires an assigned location calendar; overlapping pending/approved requests are rejected."

  def execute(conn, args) do
    with :ok <- Tool.authorize_authenticated(conn),
         {:ok, booking} <- TimeOff.report_holiday(args, Tool.current_user(conn), interface: "mcp") do
      {:ok, %{booking: Serializer.booking(booking)}}
    else
      error -> Serializer.error(error)
    end
  end
end
