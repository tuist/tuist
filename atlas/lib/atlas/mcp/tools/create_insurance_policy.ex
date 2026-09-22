defmodule Atlas.MCP.Tools.CreateInsurancePolicy do
  use Atlas.MCP.Tool,
    name: "create_insurance_policy",
    schema: %{
      "type" => "object",
      "required" => ["provider", "product", "currency", "sum_insured"],
      "properties" => %{
        "provider" => %{"type" => "string"},
        "product" => %{"type" => "string"},
        "reference" => %{"type" => "string"},
        "currency" => %{"type" => "string"},
        "sum_insured" => %{"type" => "string"},
        "provisional_cover_pct" => %{"type" => "integer", "minimum" => 0, "maximum" => 200},
        "annual_premium" => %{"type" => "string"},
        "premium_frequency" => %{
          "type" => "string",
          "enum" => Atlas.Insurance.Policy.premium_frequencies()
        },
        "deductible_per_claim" => %{"type" => "string"},
        "deductible_cap" => %{"type" => "string"},
        "mobile_use_pct" => %{"type" => "integer", "minimum" => 0, "maximum" => 100},
        "cleanup_pct" => %{"type" => "integer", "minimum" => 0, "maximum" => 100},
        "cleanup_min" => %{"type" => "string"},
        "cleanup_max" => %{"type" => "string"},
        "movement_pct" => %{"type" => "integer", "minimum" => 0, "maximum" => 100},
        "movement_min" => %{"type" => "string"},
        "movement_max" => %{"type" => "string"},
        "covers_data" => %{"type" => "boolean"},
        "covers_software" => %{"type" => "boolean"},
        "covers_dongles" => %{"type" => "boolean"},
        "covers_leased" => %{"type" => "boolean"},
        "covers_third_party_owned" => %{"type" => "boolean"},
        "starts_on" => %{"type" => "string", "format" => "date"},
        "ends_on" => %{"type" => "string", "format" => "date"},
        "quote_valid_until" => %{"type" => "string", "format" => "date"},
        "previous_policy_id" => %{"type" => "string"},
        "notes" => %{"type" => "string"}
      },
      "additionalProperties" => false
    },
    output_schema: Atlas.MCP.Serializers.Insurance.policy_schema()

  alias Atlas.Insurance.Policies
  alias Atlas.MCP.Serializers.Insurance, as: Serializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Register a new insurance policy. Executive only."
  end

  def execute(conn, args) when is_map(args) do
    with :ok <- Tool.authorize_scope(conn, "assets:write", "Hardware tools") do
      case Policies.create(args) do
        {:ok, policy} -> {:ok, Serializer.policy(policy)}
        {:error, changeset} -> {:error, "Could not create policy: #{Tool.format_changeset_errors(changeset)}"}
      end
    end
  end
end
