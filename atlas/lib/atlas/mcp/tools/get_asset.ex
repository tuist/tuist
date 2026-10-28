defmodule Atlas.MCP.Tools.GetAsset do
  use Atlas.MCP.Tool,
    name: "get_asset",
    schema: %{
      "type" => "object",
      "required" => ["asset_id"],
      "properties" => %{"asset_id" => %{"type" => "string"}},
      "additionalProperties" => false
    },
    output_schema: Atlas.MCP.Serializers.Assets.asset_schema()

  alias Atlas.Assets
  alias Atlas.MCP.Serializers.Assets, as: AssetsSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Fetch a single hardware asset by id. Executive only."
  end

  def execute(conn, %{"asset_id" => asset_id}) do
    with :ok <- Tool.authorize_scope(conn, "assets:read", "Hardware tools") do
      case Assets.get_asset(asset_id) do
        nil -> {:error, "Asset not found."}
        asset -> {:ok, AssetsSerializer.asset(asset)}
      end
    end
  end

  def execute(_conn, _args), do: {:error, "asset_id is required."}
end
