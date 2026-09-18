defmodule Atlas.MCP.Tools.RetireAsset do
  use Atlas.MCP.Tool,
    name: "retire_asset",
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
    "Retire an asset. Closes any open assignment. Executive only."
  end

  def execute(conn, %{"asset_id" => asset_id, "on" => on}) do
    with :ok <- Tool.authorize_executive(conn, "Hardware tools"),
         {:ok, date} <- Date.from_iso8601(on),
         %_{} = asset <- Assets.get_asset(asset_id) do
      case Assets.retire(asset, on: date) do
        {:ok, updated} -> {:ok, AssetsSerializer.asset(updated)}
        {:error, changeset} -> {:error, "Could not retire asset: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      {:error, _} -> {:error, "on must be an ISO 8601 date."}
      nil -> {:error, "Asset not found."}
    end
  end

  def execute(_conn, _args), do: {:error, "asset_id and on are required."}
end
