defmodule Atlas.MCP.Serializers.Insurance do
  @moduledoc false

  alias Atlas.Insurance.Claim
  alias Atlas.Insurance.ClaimAsset
  alias Atlas.Insurance.Policy
  alias Atlas.Insurance.PolicyMember
  alias Atlas.MCP.Tool

  def policy_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "provider" => %{"type" => "string"},
        "product" => %{"type" => "string"},
        "reference" => %{"type" => ["string", "null"]},
        "currency" => %{"type" => "string"},
        "sum_insured" => %{"type" => "string"},
        "provisional_cover_pct" => %{"type" => "integer"},
        "effective_cap" => %{"type" => ["string", "null"]},
        "annual_premium" => %{"type" => "string"},
        "premium_frequency" => %{"type" => "string"},
        "deductible_per_claim" => %{"type" => "string"},
        "deductible_cap" => %{"type" => ["string", "null"]},
        "mobile_use_pct" => %{"type" => "integer"},
        "cleanup_pct" => %{"type" => "integer"},
        "cleanup_min" => %{"type" => ["string", "null"]},
        "cleanup_max" => %{"type" => ["string", "null"]},
        "movement_pct" => %{"type" => "integer"},
        "movement_min" => %{"type" => ["string", "null"]},
        "movement_max" => %{"type" => ["string", "null"]},
        "covers_data" => %{"type" => "boolean"},
        "covers_software" => %{"type" => "boolean"},
        "covers_dongles" => %{"type" => "boolean"},
        "covers_leased" => %{"type" => "boolean"},
        "covers_third_party_owned" => %{"type" => "boolean"},
        "starts_on" => %{"type" => ["string", "null"], "format" => "date"},
        "ends_on" => %{"type" => ["string", "null"], "format" => "date"},
        "quote_valid_until" => %{"type" => ["string", "null"], "format" => "date"},
        "status" => %{"type" => "string"},
        "previous_policy_id" => %{"type" => ["string", "null"]},
        "insurance_policy_url" => %{"type" => "string"}
      },
      "required" => [
        "id",
        "provider",
        "product",
        "currency",
        "sum_insured",
        "provisional_cover_pct",
        "annual_premium",
        "premium_frequency",
        "deductible_per_claim",
        "status",
        "insurance_policy_url"
      ],
      "additionalProperties" => false
    }
  end

  def policy(%Policy{} = p) do
    %{
      id: p.id,
      provider: p.provider,
      product: p.product,
      reference: p.reference,
      currency: p.currency,
      sum_insured: decimal_string(p.sum_insured),
      provisional_cover_pct: p.provisional_cover_pct,
      effective_cap: decimal_string(Policy.effective_cap(p)),
      annual_premium: decimal_string(p.annual_premium),
      premium_frequency: p.premium_frequency,
      deductible_per_claim: decimal_string(p.deductible_per_claim),
      deductible_cap: decimal_string(p.deductible_cap),
      mobile_use_pct: p.mobile_use_pct,
      cleanup_pct: p.cleanup_pct,
      cleanup_min: decimal_string(p.cleanup_min),
      cleanup_max: decimal_string(p.cleanup_max),
      movement_pct: p.movement_pct,
      movement_min: decimal_string(p.movement_min),
      movement_max: decimal_string(p.movement_max),
      covers_data: p.covers_data,
      covers_software: p.covers_software,
      covers_dongles: p.covers_dongles,
      covers_leased: p.covers_leased,
      covers_third_party_owned: p.covers_third_party_owned,
      starts_on: iso_date(p.starts_on),
      ends_on: iso_date(p.ends_on),
      quote_valid_until: iso_date(p.quote_valid_until),
      status: p.status,
      previous_policy_id: p.previous_policy_id,
      insurance_policy_url: Tool.insurance_policy_url(p.id)
    }
  end

  def policy_list_schema do
    %{
      "type" => "object",
      "properties" => %{
        "policies" => %{"type" => "array", "items" => policy_schema()},
        "count" => %{"type" => "integer"}
      },
      "required" => ["policies", "count"],
      "additionalProperties" => false
    }
  end

  def policy_list(rows) do
    %{policies: Enum.map(rows, &policy/1), count: length(rows)}
  end

  def member_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "policy_id" => %{"type" => "string"},
        "asset_id" => %{"type" => "string"},
        "declared_value" => %{"type" => "string"},
        "covered_from" => %{"type" => "string", "format" => "date"},
        "covered_to" => %{"type" => ["string", "null"], "format" => "date"}
      },
      "required" => ["id", "policy_id", "asset_id", "declared_value", "covered_from"],
      "additionalProperties" => false
    }
  end

  def member(%PolicyMember{} = m) do
    %{
      id: m.id,
      policy_id: m.policy_id,
      asset_id: m.asset_id,
      declared_value: decimal_string(m.declared_value),
      covered_from: iso_date(m.covered_from),
      covered_to: iso_date(m.covered_to)
    }
  end

  def claim_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "policy_id" => %{"type" => "string"},
        "claim_reference" => %{"type" => ["string", "null"]},
        "incident_on" => %{"type" => "string", "format" => "date"},
        "incident_type" => %{"type" => "string"},
        "reported_on" => %{"type" => ["string", "null"], "format" => "date"},
        "status" => %{"type" => "string"},
        "claimed_amount" => %{"type" => ["string", "null"]},
        "payout_amount" => %{"type" => ["string", "null"]},
        "deductible_applied" => %{"type" => ["string", "null"]}
      },
      "required" => ["id", "policy_id", "incident_on", "incident_type", "status"],
      "additionalProperties" => false
    }
  end

  def claim(%Claim{} = c) do
    %{
      id: c.id,
      policy_id: c.policy_id,
      claim_reference: c.claim_reference,
      incident_on: iso_date(c.incident_on),
      incident_type: c.incident_type,
      reported_on: iso_date(c.reported_on),
      status: c.status,
      claimed_amount: decimal_string(c.claimed_amount),
      payout_amount: decimal_string(c.payout_amount),
      deductible_applied: decimal_string(c.deductible_applied)
    }
  end

  def claim_asset_schema do
    %{
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
  end

  def claim_asset(%ClaimAsset{} = link) do
    %{
      id: link.id,
      claim_id: link.claim_id,
      asset_id: link.asset_id,
      damage_amount: decimal_string(link.damage_amount)
    }
  end

  defp decimal_string(nil), do: nil
  defp decimal_string(%Decimal{} = d), do: Decimal.to_string(d, :normal)

  defp iso_date(nil), do: nil
  defp iso_date(%Date{} = d), do: Date.to_iso8601(d)
end
