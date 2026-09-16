defmodule Atlas.MCP.Tools.DisposeAsset do
  use Atlas.MCP.Tool,
    name: "dispose_asset",
    schema: %{
      "type" => "object",
      "required" => ["asset_id", "on"],
      "properties" => %{
        "asset_id" => %{"type" => "string"},
        "on" => %{"type" => "string", "format" => "date"},
        "proceeds" => %{"type" => "string"},
        "currency" => %{"type" => "string"},
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
    "Dispose of a retired asset, optionally recording proceeds and currency. Executive only."
  end

  def execute(conn, %{"asset_id" => asset_id, "on" => on} = args) do
    with :ok <- Tool.authorize_executive(conn, "Hardware tools"),
         {:ok, date} <- Date.from_iso8601(on),
         {:ok, proceeds} <- parse_decimal(Map.get(args, "proceeds")),
         %_{} = asset <- Assets.get_asset(asset_id) do
      case Assets.dispose(asset,
             on: date,
             proceeds: proceeds,
             currency: Map.get(args, "currency")
           ) do
        {:ok, updated} -> {:ok, AssetsSerializer.asset(updated)}
        {:error, changeset} -> {:error, "Could not dispose asset: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      {:error, :invalid_decimal} -> {:error, "proceeds must be a decimal string."}
      {:error, _} -> {:error, "on must be an ISO 8601 date."}
      nil -> {:error, "Asset not found."}
    end
  end

  def execute(_conn, _args), do: {:error, "asset_id and on are required."}

  defp parse_decimal(nil), do: {:ok, nil}

  defp parse_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {%Decimal{} = d, ""} -> {:ok, d}
      _ -> {:error, :invalid_decimal}
    end
  end
end
