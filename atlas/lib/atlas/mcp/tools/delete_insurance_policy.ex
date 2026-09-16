defmodule Atlas.MCP.Tools.DeleteInsurancePolicy do
  use Atlas.MCP.Tool,
    name: "delete_insurance_policy",
    schema: %{
      "type" => "object",
      "required" => ["policy_id"],
      "properties" => %{"policy_id" => %{"type" => "string"}},
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"deleted" => %{"type" => "boolean"}, "id" => %{"type" => "string"}},
      "required" => ["deleted", "id"],
      "additionalProperties" => false
    }

  alias Atlas.Insurance.Policies
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Delete an insurance policy. Rejected if it has members or claims; use expire_insurance_policy or cancel_insurance_policy to keep the historical record. Executive only."
  end

  def execute(conn, %{"policy_id" => id}) do
    with :ok <- Tool.authorize_executive(conn, "Hardware tools"),
         %_{} = policy <- Policies.get(id) do
      case Policies.delete(policy) do
        {:ok, deleted} -> {:ok, %{deleted: true, id: deleted.id}}
        {:error, changeset} -> {:error, "Could not delete policy: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      nil -> {:error, "Insurance policy not found."}
    end
  end

  def execute(_conn, _args), do: {:error, "policy_id is required."}
end
