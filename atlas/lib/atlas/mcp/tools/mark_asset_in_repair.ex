defmodule Atlas.MCP.Tools.MarkAssetInRepair do
  use Atlas.MCP.Tool,
    name: "mark_asset_in_repair",
    schema: %{
      "type" => "object",
      "required" => ["asset_id", "on"],
      "properties" => %{
        "asset_id" => %{"type" => "string"},
        "on" => %{"type" => "string", "format" => "date"}
      },
      "additionalProperties" => false
    },
    output_schema: Atlas.MCP.Serializers.Assets.asset_schema()

  alias Atlas.Assets
  alias Atlas.MCP.Serializers.Assets, as: Serializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Move an asset from storage or in_service to in_repair. Snapshots pre_repair_state so mark_asset_repaired can restore it. Executive only."
  end

  def execute(conn, %{"asset_id" => id, "on" => on}) do
    with :ok <- Tool.authorize_scope(conn, "assets:write", "Hardware tools"),
         {:ok, date} <- Date.from_iso8601(on),
         %_{} = asset <- Assets.get_asset(id) do
      case Assets.mark_in_repair(asset, on: date) do
        {:ok, updated} -> {:ok, Serializer.asset(updated)}
        {:error, changeset} -> {:error, "Could not mark in repair: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      {:error, _} -> {:error, "on must be an ISO 8601 date."}
      nil -> {:error, "Asset not found."}
    end
  end

  def execute(_conn, _args), do: {:error, "asset_id and on are required."}
end
