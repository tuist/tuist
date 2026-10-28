defmodule Atlas.MCP.Tools.ListDataCenters do
  use Atlas.MCP.Tool,
    name: "list_data_centers",
    schema: %{
      "type" => "object",
      "properties" => %{
        "status" => %{"type" => "string", "enum" => Atlas.Assets.DataCenter.statuses()},
        "page" => %{"type" => "integer", "minimum" => 1},
        "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 200}
      },
      "additionalProperties" => false
    },
    output_schema: Atlas.MCP.Serializers.DataCenters.data_center_list_schema()

  alias Atlas.Assets
  alias Atlas.MCP.Serializers.DataCenters, as: Serializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "List hardware data centers. Executive only."
  end

  def execute(conn, args) when is_map(args) do
    with :ok <- Tool.authorize_scope(conn, "assets:read", "Hardware tools") do
      filters =
        args
        |> Map.take(["status"])
        |> Enum.map(fn {k, v} -> %{field: String.to_existing_atom(k), op: :==, value: v} end)

      {rows, _meta} =
        Assets.list_data_centers(%{
          page: Map.get(args, "page", 1),
          page_size: Map.get(args, "page_size", 25),
          filters: filters
        })

      {:ok, Serializer.data_center_list(rows)}
    end
  end
end
