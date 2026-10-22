defmodule Atlas.MCP.Tools.GetTimeOffCalendar do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "get_time_off_calendar",
    schema: %{
      "type" => "object",
      "required" => ["starts_on", "ends_on"],
      "properties" => %{
        "starts_on" => %{"type" => "string", "format" => "date"},
        "ends_on" => %{"type" => "string", "format" => "date"}
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "locations" => %{"type" => "array", "items" => Atlas.MCP.Serializers.TimeOff.location_schema()},
        "people" => %{
          "type" => "array",
          "items" =>
            Atlas.MCP.Serializers.TimeOff.object(%{
              "id" => %{"type" => "string"},
              "name" => %{"type" => "string"},
              "location_id" => %{"type" => ["string", "null"]}
            })
        },
        "bookings" => %{"type" => "array", "items" => Atlas.MCP.Serializers.TimeOff.summary_schema()},
        "requests" => %{"type" => "array", "items" => Atlas.MCP.Serializers.TimeOff.summary_schema()},
        "public_holidays" => %{"type" => "array", "items" => Atlas.MCP.Serializers.TimeOff.holiday_schema()}
      },
      "required" => ["locations", "people", "bookings", "requests", "public_holidays"],
      "additionalProperties" => false
    }

  alias Atlas.MCP.Serializers.TimeOff, as: Serializer
  alias Atlas.MCP.Tool
  alias Atlas.TimeOff

  @impl EMCP.Tool
  def description,
    do:
      "Get team leave, people/location assignments, and public holidays in a date window of at most 62 days. Bookings include pending and approved leave; only approved leave is confirmed. Requests also includes rejected/cancelled history for the caller's own requests, or the whole team with time_off_approvals:read. Dates are inclusive. Working days exclude weekends and configured public holidays; missing_years indicates incomplete imports. During leave use the booking's snapshotted location, otherwise the person's current location."

  def execute(conn, args) do
    with :ok <- Tool.authorize_authenticated(conn),
         {:ok, first} <- Date.from_iso8601(args["starts_on"] || ""),
         {:ok, last} <- Date.from_iso8601(args["ends_on"] || ""),
         {:ok, data} <- TimeOff.calendar(first, last, Tool.current_user(conn)) do
      {:ok,
       %{
         locations: Enum.map(data.locations, &Serializer.location/1),
         people: Enum.map(data.users, &%{id: &1.id, name: &1.name || &1.email, location_id: &1.time_off_location_id}),
         bookings: Enum.map(data.bookings, &Serializer.summary/1),
         requests: Enum.map(data.requests, &Serializer.summary/1),
         public_holidays:
           data.holidays
           |> Enum.filter(&(Date.compare(&1.date, first) != :lt and Date.compare(&1.date, last) != :gt))
           |> Enum.map(&Serializer.holiday/1)
       }}
    else
      error -> Serializer.error(error)
    end
  end
end
