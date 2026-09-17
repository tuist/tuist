defmodule Atlas.MCP.Tools.EditAssetMetadata do
  use Atlas.MCP.Tool,
    name: "edit_asset_metadata",
    schema: %{
      "type" => "object",
      "required" => ["asset_id"],
      "properties" => %{
        "asset_id" => %{"type" => "string"},
        "name" => %{"type" => "string"},
        "asset_tag" => %{"type" => "string"},
        "serial_number" => %{"type" => "string"},
        "manufacturer" => %{"type" => "string"},
        "model" => %{"type" => "string"},
        "category" => %{"type" => "string", "enum" => Atlas.Assets.Asset.categories()},
        "location" => %{"type" => "string", "enum" => Atlas.Assets.Asset.locations()},
        "location_detail" => %{"type" => "string"},
        "warranty_end_on" => %{"type" => "string", "format" => "date"},
        "vendor" => %{"type" => "string"},
        "finance_transaction_id" => %{"type" => "string"},
        "finance_invoice_id" => %{"type" => "string"},
        "purchase_document_id" => %{"type" => "string"},
        "notes" => %{"type" => "string"}
      },
      "additionalProperties" => false
    },
    output_schema: Atlas.MCP.Serializers.Assets.asset_schema()

  alias Atlas.Assets
  alias Atlas.MCP.Serializers.Assets, as: Serializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Edit non-lifecycle metadata on an existing hardware asset. Executive only."
  end

  def execute(conn, %{"asset_id" => asset_id} = args) do
    with :ok <- Tool.authorize_executive(conn, "Hardware tools"),
         %_{} = asset <- Assets.get_asset(asset_id) do
      attrs = Map.delete(args, "asset_id")

      case Assets.edit_metadata(asset, attrs) do
        {:ok, updated} -> {:ok, Serializer.asset(updated)}
        {:error, changeset} -> {:error, "Could not edit asset: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      nil -> {:error, "Asset not found."}
    end
  end

  def execute(_conn, _args), do: {:error, "asset_id is required."}
end
