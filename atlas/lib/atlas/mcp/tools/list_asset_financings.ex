defmodule Atlas.MCP.Tools.ListAssetFinancings do
  use Atlas.MCP.Tool,
    name: "list_asset_financings",
    schema: %{
      "type" => "object",
      "required" => ["asset_id"],
      "properties" => %{"asset_id" => %{"type" => "string"}},
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "asset_id" => %{"type" => "string"},
        "financings" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "line_id" => %{"type" => "string"},
              "financing_id" => %{"type" => "string"},
              "share_basis_points" => %{"type" => "integer"},
              "type" => %{"type" => "string"},
              "status" => %{"type" => "string"},
              "provider" => %{"type" => "string"},
              "supplier" => %{"type" => ["string", "null"]},
              "reference" => %{"type" => ["string", "null"]},
              "financing_url" => %{"type" => "string"}
            },
            "required" => [
              "line_id",
              "financing_id",
              "share_basis_points",
              "type",
              "status",
              "provider",
              "financing_url"
            ],
            "additionalProperties" => false
          }
        },
        "count" => %{"type" => "integer"}
      },
      "required" => ["asset_id", "financings", "count"],
      "additionalProperties" => false
    }

  alias Atlas.Assets
  alias Atlas.Finance.Financings
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "List financing arrangements connected to one hardware asset, including the allocation share. Executive only."
  end

  def execute(conn, %{"asset_id" => asset_id}) do
    with :ok <- Tool.authorize_executive(conn, "Hardware tools"),
         %_{} <- Assets.get_asset(asset_id) do
      rows = Financings.list_asset_financings(asset_id)

      financings =
        Enum.map(rows, fn line ->
          %{
            line_id: line.id,
            financing_id: line.financing_id,
            share_basis_points: line.share_bps,
            type: line.financing.type,
            status: line.financing.status,
            provider: line.financing.provider,
            supplier: line.financing.supplier,
            reference: line.financing.reference,
            financing_url: Tool.financing_url(line.financing_id)
          }
        end)

      {:ok, %{asset_id: asset_id, financings: financings, count: length(financings)}}
    else
      nil -> {:error, "Asset not found."}
      other -> other
    end
  end

  def execute(_conn, _args), do: {:error, "asset_id is required."}
end
