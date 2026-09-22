defmodule Atlas.MCP.Tools.DeleteAsset do
  use Atlas.MCP.Tool,
    name: "delete_asset",
    schema: %{
      "type" => "object",
      "required" => ["asset_id"],
      "properties" => %{"asset_id" => %{"type" => "string"}},
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"asset_id" => %{"type" => "string"}, "deleted" => %{"type" => "boolean"}},
      "required" => ["asset_id", "deleted"],
      "additionalProperties" => false
    }

  alias Atlas.Assets
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Permanently delete a hardware asset. Rejects if the asset has any history (assignments, events, or financing links) so history-carrying devices must be retired or disposed instead. Executive only."
  end

  def execute(conn, %{"asset_id" => asset_id}) do
    with :ok <- Tool.authorize_scope(conn, "assets:write", "Hardware tools"),
         %_{} = asset <- Assets.get_asset(asset_id) do
      case Assets.delete_asset(asset) do
        {:ok, deleted} -> {:ok, %{asset_id: deleted.id, deleted: true}}
        {:error, changeset} -> {:error, "Could not delete asset: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      nil -> {:error, "Asset not found."}
    end
  end

  def execute(_conn, _args), do: {:error, "asset_id is required."}
end
