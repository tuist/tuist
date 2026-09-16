defmodule Atlas.MCP.Tools.GetInsurancePolicy do
  use Atlas.MCP.Tool,
    name: "get_insurance_policy",
    schema: %{
      "type" => "object",
      "required" => ["policy_id"],
      "properties" => %{"policy_id" => %{"type" => "string"}},
      "additionalProperties" => false
    },
    output_schema: Atlas.MCP.Serializers.Insurance.policy_schema()

  alias Atlas.Insurance.Policies
  alias Atlas.MCP.Serializers.Insurance, as: Serializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Fetch a single insurance policy. Executive only."
  end

  def execute(conn, %{"policy_id" => id}) do
    with :ok <- Tool.authorize_executive(conn, "Hardware tools") do
      case Policies.get(id) do
        nil -> {:error, "Insurance policy not found."}
        policy -> {:ok, Serializer.policy(policy)}
      end
    end
  end

  def execute(_conn, _args), do: {:error, "policy_id is required."}
end
