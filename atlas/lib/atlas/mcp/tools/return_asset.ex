defmodule Atlas.MCP.Tools.ReturnAsset do
  use Atlas.MCP.Tool,
    name: "return_asset",
    schema: %{
      "type" => "object",
      "required" => ["asset_id", "on"],
      "properties" => %{
        "asset_id" => %{"type" => "string"},
        "on" => %{"type" => "string", "format" => "date"},
        "notes" => %{"type" => "string"}
      },
      "additionalProperties" => false
    },
    output_schema: Atlas.MCP.Serializers.Assets.asset_schema()

  alias Atlas.Assets
  alias Atlas.MCP.Serializers.Assets, as: AssetsSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Close the open assignment for an asset and move it back to in_storage. Executive only."
  end

  def execute(conn, %{"asset_id" => asset_id, "on" => on} = args) do
    with :ok <- Tool.authorize_executive(conn, "Hardware tools"),
         {:ok, date} <- parse_date(on),
         %_{} = asset <- Assets.get_asset(asset_id) do
      case Assets.return_asset(asset, on: date, notes: Map.get(args, "notes")) do
        {:ok, updated} -> {:ok, AssetsSerializer.asset(updated)}
        {:error, changeset} -> {:error, "Could not return asset: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      {:error, :invalid_date} -> {:error, "on must be an ISO 8601 date."}
      nil -> {:error, "Asset not found."}
      other -> other
    end
  end

  def execute(_conn, _args), do: {:error, "asset_id and on are required."}

  defp parse_date(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      _ -> {:error, :invalid_date}
    end
  end
end
