defmodule Atlas.MCP.Tools.ListAssetAssignments do
  use Atlas.MCP.Tool,
    name: "list_asset_assignments",
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
    output_schema: Atlas.MCP.Serializers.Assets.assignment_list_schema()

  alias Atlas.Assets
  alias Atlas.MCP.Serializers.Assets, as: AssetsSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "List custody intervals for an asset, most recent first. Executive only."
  end

  def execute(conn, %{"asset_id" => asset_id} = args) do
    with :ok <- Tool.authorize_scope(conn, "assets:read", "Hardware tools") do
      case Assets.get_asset(asset_id) do
        nil ->
          {:error, "Asset not found."}

        asset ->
          {assignments, _meta} =
            Assets.list_assignments(asset, %{
              page: Map.get(args, "page", 1),
              page_size: Map.get(args, "page_size", 25)
            })

          {:ok, AssetsSerializer.assignment_list(assignments)}
      end
    end
  end

  def execute(_conn, _args), do: {:error, "asset_id is required."}
end
