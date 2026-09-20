defmodule Atlas.MCP.Tools.UnlinkAssetFromInsuranceClaim do
  use Atlas.MCP.Tool,
    name: "unlink_asset_from_insurance_claim",
    schema: %{
      "type" => "object",
      "required" => ["claim_id", "asset_id"],
      "properties" => %{
        "claim_id" => %{"type" => "string"},
        "asset_id" => %{"type" => "string"}
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"deleted" => %{"type" => "boolean"}},
      "required" => ["deleted"],
      "additionalProperties" => false
    }

  alias Atlas.Insurance.Policies
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Remove an asset from an insurance claim's affected-asset list. Executive only."
  end

  def execute(conn, %{"claim_id" => claim_id, "asset_id" => asset_id}) do
    with :ok <- Tool.authorize_scope(conn, "assets:write", "Hardware tools"),
         %_{} = claim <- Policies.get_claim(claim_id) do
      case Policies.unlink_asset_from_claim(claim, asset_id) do
        {:ok, _} -> {:ok, %{deleted: true}}
        {:error, :not_found} -> {:error, "Link not found."}
        {:error, changeset} -> {:error, "Could not unlink asset: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      nil -> {:error, "Insurance claim not found."}
    end
  end

  def execute(_conn, _args), do: {:error, "claim_id and asset_id are required."}
end
