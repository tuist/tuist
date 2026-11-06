defmodule Atlas.MCP.Tools.ReviewHoliday do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "review_holiday",
    schema: %{
      "type" => "object",
      "required" => ["id", "decision"],
      "properties" => %{
        "id" => %{"type" => "string"},
        "decision" => %{"type" => "string", "enum" => ["approved", "rejected"]}
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
      "Approve or reject a pending holiday request with time_off_approvals:write. Cannot review your own request or an already reviewed/cancelled request. No manager hierarchy is required."

  def execute(conn, %{"id" => id, "decision" => decision}) do
    with :ok <- Tool.authorize_scope(conn, "time_off_approvals:write", "Holiday approvals"),
         {:ok, booking} <- TimeOff.review_holiday(id, decision, Tool.current_user(conn), interface: "mcp") do
      {:ok, %{booking: Serializer.booking(booking)}}
    else
      error -> Serializer.error(error)
    end
  end
end
