defmodule Atlas.MCP.Tools.CreateAsset do
  use Atlas.MCP.Tool,
    name: "create_asset",
    schema: %{
      "type" => "object",
      "required" => [
        "name",
        "category",
        "acquisition_cost",
        "acquisition_currency"
      ],
      "properties" => %{
        "name" => %{"type" => "string"},
        "asset_tag" => %{"type" => "string"},
        "serial_number" => %{"type" => "string"},
        "manufacturer" => %{"type" => "string"},
        "model" => %{"type" => "string"},
        "category" => %{"type" => "string", "enum" => Atlas.Assets.Asset.categories()},
        "location" => %{"type" => "string", "enum" => Atlas.Assets.Asset.locations()},
        "location_detail" => %{"type" => "string"},
        "ownership" => %{"type" => "string", "enum" => Atlas.Assets.Asset.ownership_values()},
        "ownership_acquired_on" => %{"type" => "string", "format" => "date"},
        "purchased_on" => %{"type" => "string", "format" => "date"},
        "acquisition_cost" => %{"type" => "string"},
        "acquisition_currency" => %{"type" => "string"},
        "useful_life_months" => %{"type" => "integer"},
        "salvage_value" => %{"type" => "string"},
        "valuation_treatment" => %{
          "type" => "string",
          "enum" => Atlas.Assets.Asset.valuation_treatments()
        },
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
  alias Atlas.MCP.Serializers.Assets, as: AssetsSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Register a new hardware asset with its acquisition details. Executive only."
  end

  def execute(conn, args) when is_map(args) do
    with :ok <- Tool.authorize_scope(conn, "assets:write", "Hardware tools") do
      case Assets.create_asset(args) do
        {:ok, asset} -> {:ok, AssetsSerializer.asset(asset)}
        {:error, changeset} -> {:error, "Could not create asset: #{Tool.format_changeset_errors(changeset)}"}
      end
    end
  end
end
