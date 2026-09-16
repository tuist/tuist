defmodule Atlas.MCP.Tools.GetDataCenter do
  use Atlas.MCP.Tool,
    name: "get_data_center",
    schema: %{
      "type" => "object",
      "required" => ["data_center_id"],
      "properties" => %{"data_center_id" => %{"type" => "string"}},
      "additionalProperties" => false
    },
    output_schema: Atlas.MCP.Serializers.DataCenters.data_center_schema()

  alias Atlas.Assets
  alias Atlas.MCP.Serializers.DataCenters, as: Serializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Fetch a single hardware data center by id. Executive only."
  end

  def execute(conn, %{"data_center_id" => id}) do
    with :ok <- Tool.authorize_executive(conn, "Hardware tools") do
      case Assets.get_data_center(id) do
        nil -> {:error, "Data center not found."}
        dc -> {:ok, Serializer.data_center(dc)}
      end
    end
  end

  def execute(_conn, _args), do: {:error, "data_center_id is required."}
end
