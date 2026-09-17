defmodule Atlas.MCP.Tools.ActivateInsurancePolicy do
  use Atlas.MCP.Tool,
    name: "activate_insurance_policy",
    schema: %{
      "type" => "object",
      "required" => ["policy_id"],
      "properties" => %{
        "policy_id" => %{"type" => "string"},
        "starts_on" => %{"type" => "string", "format" => "date"}
      },
      "additionalProperties" => false
    },
    output_schema: Atlas.MCP.Serializers.Insurance.policy_schema()

  alias Atlas.Insurance.Policies
  alias Atlas.MCP.Serializers.Insurance, as: Serializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Activate a quoted insurance policy. Optionally sets the start date. Executive only."
  end

  def execute(conn, %{"policy_id" => id} = args) do
    with :ok <- Tool.authorize_executive(conn, "Hardware tools"),
         %_{} = policy <- Policies.get(id) do
      opts =
        case Map.get(args, "starts_on") do
          nil -> []
          value -> [starts_on: Date.from_iso8601!(value)]
        end

      case Policies.activate(policy, opts) do
        {:ok, updated} -> {:ok, Serializer.policy(updated)}
        {:error, :invalid_state_transition} -> {:error, "Policy cannot be activated from its current state."}
        {:error, changeset} -> {:error, "Could not activate policy: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      nil -> {:error, "Insurance policy not found."}
    end
  end

  def execute(_conn, _args), do: {:error, "policy_id is required."}
end
