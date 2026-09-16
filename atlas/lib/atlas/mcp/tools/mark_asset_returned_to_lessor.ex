defmodule Atlas.MCP.Tools.MarkAssetReturnedToLessor do
  use Atlas.MCP.Tool,
    name: "mark_asset_returned_to_lessor",
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
    "Mark a leased asset as returned to the lessor at end of term (option not exercised). Executive only."
  end

  def execute(conn, %{"asset_id" => asset_id, "on" => on}) do
    with :ok <- Tool.authorize_executive(conn, "Hardware tools"),
         %_{} = asset <- Assets.get_asset(asset_id) do
      case Assets.mark_returned_to_lessor(asset, on: Date.from_iso8601!(on)) do
        {:ok, updated} -> {:ok, Serializer.asset(updated)}
        {:error, changeset} -> {:error, "Could not mark returned: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      nil -> {:error, "Asset not found."}
    end
  end

  def execute(_conn, _args), do: {:error, "asset_id and on are required."}
end
