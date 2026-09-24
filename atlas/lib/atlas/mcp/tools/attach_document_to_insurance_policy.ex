defmodule Atlas.MCP.Tools.AttachDocumentToInsurancePolicy do
  use Atlas.MCP.Tool,
    name: "attach_document_to_insurance_policy",
    schema: %{
      "type" => "object",
      "required" => ["policy_id", "document_id", "kind"],
      "properties" => %{
        "policy_id" => %{"type" => "string"},
        "document_id" => %{"type" => "string"},
        "kind" => %{
          "type" => "string",
          "enum" => Atlas.Insurance.PolicyDocument.kinds()
        },
        "notes" => %{"type" => "string"}
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "policy_id" => %{"type" => "string"},
        "document_id" => %{"type" => "string"},
        "kind" => %{"type" => "string"}
      },
      "required" => ["id", "policy_id", "document_id", "kind"],
      "additionalProperties" => false
    }

  alias Atlas.Insurance.Policies
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Attach an Atlas document to an insurance policy with a kind (quote, policy, avb, renewal, endorsement, other). Executive only."
  end

  def execute(conn, %{"policy_id" => policy_id, "document_id" => document_id, "kind" => kind} = args) do
    with :ok <- Tool.authorize_scope(conn, "assets:write", "Hardware tools"),
         %_{} = policy <- Policies.get(policy_id) do
      opts =
        case Map.get(args, "notes") do
          nil -> []
          value -> [notes: value]
        end

      case Policies.attach_document_to_policy(policy, document_id, kind, opts) do
        {:ok, link} ->
          {:ok, %{id: link.id, policy_id: link.policy_id, document_id: link.document_id, kind: link.kind}}

        {:error, :document_not_found} ->
          {:error, "Document not found."}

        {:error, changeset} ->
          {:error, "Could not attach document: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      nil -> {:error, "Insurance policy not found."}
    end
  end

  def execute(_conn, _args), do: {:error, "policy_id, document_id, and kind are required."}
end
