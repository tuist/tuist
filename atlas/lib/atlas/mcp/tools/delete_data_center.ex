defmodule Atlas.MCP.Tools.DeleteDataCenter do
  use Atlas.MCP.Tool,
    name: "delete_data_center",
    schema: %{
      "type" => "object",
      "required" => ["data_center_id"],
      "properties" => %{"data_center_id" => %{"type" => "string"}},
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"deleted" => %{"type" => "boolean"}, "id" => %{"type" => "string"}},
      "required" => ["deleted", "id"],
      "additionalProperties" => false
    }

  alias Atlas.Assets
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Delete a data center. Rejected while it still hosts assets; move them elsewhere first, or use decommission_data_center to keep the historical record. Executive only."
  end

  def execute(conn, %{"data_center_id" => id}) do
    with :ok <- Tool.authorize_executive(conn, "Hardware tools"),
         %_{} = dc <- Assets.get_data_center(id) do
      case Assets.delete_data_center(dc) do
        {:ok, deleted} -> {:ok, %{deleted: true, id: deleted.id}}
        {:error, changeset} -> {:error, "Could not delete data center: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      nil -> {:error, "Data center not found."}
    end
  end

  def execute(_conn, _args), do: {:error, "data_center_id is required."}
end
