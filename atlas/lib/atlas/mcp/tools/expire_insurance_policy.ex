defmodule Atlas.MCP.Tools.ExpireInsurancePolicy do
  use Atlas.MCP.Tool,
    name: "expire_insurance_policy",
    schema: %{
      "type" => "object",
      "required" => ["policy_id"],
      "properties" => %{
        "policy_id" => %{"type" => "string"},
        "ends_on" => %{"type" => "string", "format" => "date"}
      },
      "additionalProperties" => false
    },
    output_schema: Atlas.MCP.Serializers.Insurance.policy_schema()

  alias Atlas.Insurance.Policies
  alias Atlas.MCP.Serializers.Insurance, as: Serializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Mark an insurance policy as expired and close all open members on the given date. Executive only."
  end

  def execute(conn, %{"policy_id" => id} = args) do
    with :ok <- Tool.authorize_scope(conn, "assets:write", "Hardware tools"),
         %_{} = policy <- Policies.get(id) do
      opts =
        case Map.get(args, "ends_on") do
          nil -> []
          value -> [ends_on: Date.from_iso8601!(value)]
        end

      case Policies.expire(policy, opts) do
        {:ok, updated} -> {:ok, Serializer.policy(updated)}
        {:error, changeset} -> {:error, "Could not expire policy: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      nil -> {:error, "Insurance policy not found."}
    end
  end

  def execute(_conn, _args), do: {:error, "policy_id is required."}
end
