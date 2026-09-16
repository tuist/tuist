defmodule Atlas.MCP.Tools.ListAssetEvents do
  use Atlas.MCP.Tool,
    name: "list_asset_events",
    schema: %{
      "type" => "object",
      "required" => ["asset_id"],
      "properties" => %{
        "asset_id" => %{"type" => "string"},
        "page" => %{"type" => "integer", "minimum" => 1},
        "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 200}
      },
      "additionalProperties" => false
    },
    output_schema: Atlas.MCP.Serializers.Assets.event_list_schema()

  alias Atlas.Assets
  alias Atlas.MCP.Serializers.Assets, as: AssetsSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "List physical events (repairs, incidents, warranty extensions, notes) for an asset. Executive only."
  end

  def execute(conn, %{"asset_id" => asset_id} = args) do
    with :ok <- Tool.authorize_executive(conn, "Hardware tools") do
      case Assets.get_asset(asset_id) do
        nil ->
          {:error, "Asset not found."}

        asset ->
          {events, _meta} =
            Assets.list_events(asset, %{
              page: Map.get(args, "page", 1),
              page_size: Map.get(args, "page_size", 25)
            })

          {:ok, AssetsSerializer.event_list(events)}
      end
    end
  end

  def execute(_conn, _args), do: {:error, "asset_id is required."}
end
