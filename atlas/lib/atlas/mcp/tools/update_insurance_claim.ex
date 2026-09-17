defmodule Atlas.MCP.Tools.UpdateInsuranceClaim do
  use Atlas.MCP.Tool,
    name: "update_insurance_claim",
    schema: %{
      "type" => "object",
      "required" => ["claim_id"],
      "properties" => %{
        "claim_id" => %{"type" => "string"},
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
        "notes" => %{"type" => "string"}
      },
      "additionalProperties" => false
    },
    output_schema: Atlas.MCP.Serializers.Insurance.claim_schema()

  alias Atlas.Insurance.Policies
  alias Atlas.MCP.Serializers.Insurance, as: Serializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Update the status or amounts on an insurance claim. Executive only."
  end

  def execute(conn, %{"claim_id" => id} = args) do
    with :ok <- Tool.authorize_executive(conn, "Hardware tools"),
         %_{} = claim <- Policies.get_claim(id) do
      attrs = args |> Map.delete("claim_id") |> normalize()

      case Policies.update_claim(claim, attrs) do
        {:ok, updated} -> {:ok, Serializer.claim(updated)}
        {:error, changeset} -> {:error, "Could not update claim: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      nil -> {:error, "Insurance claim not found."}
    end
  end

  def execute(_conn, _args), do: {:error, "claim_id is required."}

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
