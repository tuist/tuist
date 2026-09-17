defmodule Atlas.MCP.Tools.GetAssetBookValue do
  use Atlas.MCP.Tool,
    name: "get_asset_book_value",
    schema: %{
      "type" => "object",
      "required" => ["asset_id"],
      "properties" => %{
        "asset_id" => %{"type" => "string"},
        "on" => %{"type" => "string", "format" => "date"}
      },
      "additionalProperties" => false
    },
    output_schema: Atlas.MCP.Serializers.Assets.book_value_schema()

  alias Atlas.Assets
  alias Atlas.MCP.Serializers.Assets, as: AssetsSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Estimated book value of an asset on a given date under current assumptions. Executive only."
  end

  def execute(conn, %{"asset_id" => asset_id} = args) do
    with :ok <- Tool.authorize_executive(conn, "Hardware tools"),
         %_{} = asset <- Assets.get_asset(asset_id),
         {:ok, date} <- parse_date(Map.get(args, "on")) do
      {:ok, AssetsSerializer.book_value(asset, on: date)}
    else
      nil -> {:error, "Asset not found."}
      {:error, :invalid_date} -> {:error, "on must be an ISO 8601 date."}
      other -> other
    end
  end

  def execute(_conn, _args), do: {:error, "asset_id is required."}

  defp parse_date(nil), do: {:ok, Date.utc_today()}

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      _ -> {:error, :invalid_date}
    end
  end
end
