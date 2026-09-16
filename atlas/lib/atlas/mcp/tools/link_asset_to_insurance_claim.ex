defmodule Atlas.MCP.Tools.LinkAssetToInsuranceClaim do
  use Atlas.MCP.Tool,
    name: "link_asset_to_insurance_claim",
    schema: %{
      "type" => "object",
      "required" => ["claim_id", "asset_id"],
      "properties" => %{
        "claim_id" => %{"type" => "string"},
        "asset_id" => %{"type" => "string"},
        "damage_amount" => %{"type" => "string"},
        "notes" => %{"type" => "string"}
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "claim_id" => %{"type" => "string"},
        "asset_id" => %{"type" => "string"},
        "damage_amount" => %{"type" => ["string", "null"]}
      },
      "required" => ["id", "claim_id", "asset_id"],
      "additionalProperties" => false
    }

  alias Atlas.Insurance.Policies
  alias Atlas.MCP.Serializers.Insurance, as: Serializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Add an affected asset to an existing insurance claim, optionally with a per-asset damage amount. Executive only."
  end

  def execute(conn, %{"claim_id" => claim_id, "asset_id" => asset_id} = args) do
    with :ok <- Tool.authorize_executive(conn, "Hardware tools"),
         %_{} = claim <- Policies.get_claim(claim_id) do
      attrs =
        args
        |> Map.drop(["claim_id", "asset_id"])
        |> normalize()

      case Policies.link_asset_to_claim(claim, asset_id, attrs) do
        {:ok, link} -> {:ok, Serializer.claim_asset(link)}
        {:error, changeset} -> {:error, "Could not link asset: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      nil -> {:error, "Insurance claim not found."}
    end
  end

  def execute(_conn, _args), do: {:error, "claim_id and asset_id are required."}

  defp normalize(attrs) do
    attrs
    |> Map.new(fn
      {"damage_amount", v} -> {:damage_amount, Decimal.new(v)}
      {"notes", v} -> {:notes, v}
      {k, v} -> {String.to_existing_atom(k), v}
    end)
  end
end
