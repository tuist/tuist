defmodule Atlas.MCP.Tools.InstallAssetInDataCenter do
  use Atlas.MCP.Tool,
    name: "install_asset_in_data_center",
    schema: %{
      "type" => "object",
      "required" => ["asset_id", "data_center_id"],
      "properties" => %{
        "asset_id" => %{"type" => "string"},
        "data_center_id" => %{"type" => "string"},
        "location_detail" => %{"type" => "string"}
      },
      "additionalProperties" => false
    },
    output_schema: Atlas.MCP.Serializers.Assets.asset_schema()

  alias Atlas.Assets
  alias Atlas.MCP.Serializers.Assets, as: AssetSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Install a hardware asset in a data center. Sets location to data_center and links the asset to the given facility. Executive only."
  end

  def execute(conn, %{"asset_id" => asset_id, "data_center_id" => dc_id} = args) do
    with :ok <- Tool.authorize_executive(conn, "Hardware tools"),
         %_{} = asset <- Assets.get_asset(asset_id),
         %_{} = dc <- Assets.get_data_center(dc_id) do
      opts =
        case Map.get(args, "location_detail") do
          nil -> []
          value -> [location_detail: value]
        end

      case Assets.install_asset_in_data_center(asset, dc, opts) do
        {:ok, updated} -> {:ok, AssetSerializer.asset(updated)}
        {:error, changeset} -> {:error, "Could not install asset: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      nil -> {:error, "Asset or data center not found."}
    end
  end

  def execute(_conn, _args), do: {:error, "asset_id and data_center_id are required."}
end
