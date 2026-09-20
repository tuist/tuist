defmodule Atlas.MCP.Tools.ListAssets do
  use Atlas.MCP.Tool,
    name: "list_assets",
    schema: %{
      "type" => "object",
      "properties" => %{
        "query" => %{
          "type" => "string",
          "description" => "Search by name, serial number, asset tag, manufacturer, or model."
        },
        "state" => %{"type" => "string", "enum" => Atlas.Assets.Asset.states()},
        "category" => %{"type" => "string", "enum" => Atlas.Assets.Asset.categories()},
        "location" => %{"type" => "string", "enum" => Atlas.Assets.Asset.locations()},
        "holder_id" => %{"type" => "string"},
        "page" => %{"type" => "integer", "minimum" => 1},
        "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 200}
      },
      "additionalProperties" => false
    },
    output_schema: Atlas.MCP.Serializers.Assets.asset_list_schema()

  alias Atlas.Assets
  alias Atlas.MCP.Serializers.Assets, as: AssetsSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "List hardware assets with optional filters by state, category, location, and holder. Executive only."
  end

  def execute(conn, args) when is_map(args) do
    with :ok <- Tool.authorize_scope(conn, "assets:read", "Hardware tools") do
      filters =
        args
        |> Map.take(["state", "category", "location", "holder_id"])
        |> Enum.map(fn
          {"holder_id", v} -> %{field: :assigned_to_id, op: :==, value: v}
          {k, v} -> %{field: String.to_existing_atom(k), op: :==, value: v}
        end)

      params = %{
        page: Map.get(args, "page", 1),
        page_size: Map.get(args, "page_size", 25),
        filters: filters
      }

      {assets, _meta} = Assets.list_assets(params, query: Map.get(args, "query"))
      {:ok, AssetsSerializer.asset_list(assets)}
    end
  end
end
