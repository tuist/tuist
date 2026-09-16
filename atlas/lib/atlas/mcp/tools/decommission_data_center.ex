defmodule Atlas.MCP.Tools.DecommissionDataCenter do
  use Atlas.MCP.Tool,
    name: "decommission_data_center",
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
    "Mark a data center as decommissioned. Rejected while it still hosts active assets. Executive only."
  end

  def execute(conn, %{"data_center_id" => id}) do
    with :ok <- Tool.authorize_executive(conn, "Hardware tools"),
         %_{} = dc <- Assets.get_data_center(id) do
      case Assets.decommission_data_center(dc) do
        {:ok, updated} ->
          {:ok, Serializer.data_center(updated)}

        {:error, changeset} ->
          {:error, "Could not decommission data center: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      nil -> {:error, "Data center not found."}
    end
  end

  def execute(_conn, _args), do: {:error, "data_center_id is required."}
end
