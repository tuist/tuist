defmodule Atlas.MCP.Tools.EditInsurancePolicy do
  use Atlas.MCP.Tool,
    name: "edit_insurance_policy",
    schema: %{
      "type" => "object",
      "required" => ["policy_id"],
      "properties" => %{
        "policy_id" => %{"type" => "string"},
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
    "Edit metadata on an insurance policy. Executive only."
  end

  def execute(conn, %{"policy_id" => id} = args) do
    with :ok <- Tool.authorize_executive(conn, "Hardware tools"),
         %_{} = policy <- Policies.get(id) do
      attrs = Map.delete(args, "policy_id")

      case Policies.edit_metadata(policy, attrs) do
        {:ok, updated} -> {:ok, Serializer.policy(updated)}
        {:error, changeset} -> {:error, "Could not edit policy: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      nil -> {:error, "Insurance policy not found."}
    end
  end

  def execute(_conn, _args), do: {:error, "policy_id is required."}
end
