defmodule Atlas.MCP.Tools.GetTimeOffOverview do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "get_time_off_overview",
    schema: %{
      "type" => "object",
      "properties" => %{
        "location_id" => %{
          "type" => "string",
          "description" => "Filter upcoming team leave and public holidays, not the caller's own requests."
        },
        "from" => %{
          "type" => "string",
          "format" => "date",
          "description" => "Defaults to today's UTC date. Includes ongoing leave."
        },
        "upcoming_page" => %{"type" => "integer", "minimum" => 1},
        "requests_page" => %{"type" => "integer", "minimum" => 1},
        "holidays_page" => %{"type" => "integer", "minimum" => 1},
        "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 50}
      }
    },
    output_schema:
      Atlas.MCP.Serializers.TimeOff.object(%{
        "upcoming" => Atlas.MCP.Serializers.TimeOff.page_schema(Atlas.MCP.Serializers.TimeOff.summary_schema()),
        "my_requests" => Atlas.MCP.Serializers.TimeOff.page_schema(Atlas.MCP.Serializers.TimeOff.summary_schema()),
        "public_holidays" => Atlas.MCP.Serializers.TimeOff.page_schema(Atlas.MCP.Serializers.TimeOff.holiday_schema())
      })

  alias Atlas.MCP.Serializers.TimeOff, as: Serializer
  alias Atlas.MCP.Tool
  alias Atlas.TimeOff

  @impl EMCP.Tool
  def description,
    do:
      "Get paginated upcoming team leave, the caller's own requests (including past/rejected/cancelled), and upcoming public holidays. Pending leave is not confirmed."

  def execute(conn, args) do
    with :ok <- Tool.authorize_authenticated(conn),
         {:ok, first} <- Date.from_iso8601(args["from"] || Date.to_iso8601(Date.utc_today())) do
      data =
        TimeOff.overview(Tool.current_user(conn),
          from: first,
          location_id: args["location_id"],
          upcoming_page: args["upcoming_page"],
          requests_page: args["requests_page"],
          holidays_page: args["holidays_page"],
          page_size: args["page_size"]
        )

      {:ok,
       %{
         upcoming: Serializer.page(Enum.map(data.upcoming, &Serializer.summary/1), data.upcoming_meta),
         my_requests: Serializer.page(Enum.map(data.mine, &Serializer.summary/1), data.mine_meta),
         public_holidays: Serializer.page(Enum.map(data.public_holidays, &Serializer.holiday/1), data.holidays_meta)
       }}
    else
      error -> Serializer.error(error)
    end
  end
end
