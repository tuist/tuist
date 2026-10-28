defmodule Atlas.MCP.Tools.RecordInsuranceClaim do
  use Atlas.MCP.Tool,
    name: "record_insurance_claim",
    schema: %{
      "type" => "object",
      "required" => ["policy_id", "incident_on", "incident_type"],
      "properties" => %{
        "policy_id" => %{"type" => "string"},
        "claim_reference" => %{"type" => "string"},
        "incident_on" => %{"type" => "string", "format" => "date"},
        "incident_type" => %{
          "type" => "string",
          "enum" => Atlas.Insurance.Claim.incident_types()
        },
        "reported_on" => %{"type" => "string", "format" => "date"},
        "status" => %{"type" => "string", "enum" => Atlas.Insurance.Claim.statuses()},
        "claimed_amount" => %{"type" => "string"},
        "payout_amount" => %{"type" => "string"},
        "deductible_applied" => %{"type" => "string"},
        "notes" => %{"type" => "string"},
        "asset_ids" => %{
          "type" => "array",
          "items" => %{"type" => "string"}
        }
      },
      "additionalProperties" => false
    },
    output_schema: Atlas.MCP.Serializers.Insurance.claim_schema()

  alias Atlas.Insurance.Policies
  alias Atlas.MCP.Serializers.Insurance, as: Serializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Record an insurance claim against a policy, optionally linking one or more affected assets. Executive only."
  end

  def execute(conn, %{"policy_id" => policy_id} = args) do
    with :ok <- Tool.authorize_scope(conn, "assets:write", "Hardware tools"),
         %_{} = policy <- Policies.get(policy_id) do
      asset_ids = Map.get(args, "asset_ids", [])
      attrs = args |> Map.drop(["policy_id", "asset_ids"]) |> normalize()

      case Policies.create_claim(policy, attrs) do
        {:ok, claim} ->
          Enum.each(asset_ids, fn asset_id ->
            Policies.link_asset_to_claim(claim, asset_id)
          end)

          {:ok, Serializer.claim(claim)}

        {:error, changeset} ->
          {:error, "Could not create claim: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      nil -> {:error, "Insurance policy not found."}
    end
  end

  def execute(_conn, _args), do: {:error, "policy_id, incident_on, and incident_type are required."}

  defp normalize(attrs) do
    attrs
    |> Map.new(fn
      {"incident_on", v} -> {:incident_on, Date.from_iso8601!(v)}
      {"reported_on", v} -> {:reported_on, Date.from_iso8601!(v)}
      {"incident_type", v} -> {:incident_type, v}
      {"status", v} -> {:status, v}
      {"notes", v} -> {:notes, v}
      {"claim_reference", v} -> {:claim_reference, v}
      {k, v} when is_binary(v) -> {String.to_existing_atom(k), Decimal.new(v)}
      {k, v} -> {String.to_existing_atom(k), v}
    end)
  end
end
