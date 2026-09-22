defmodule Atlas.MCP.Tools.AttachDocumentToInsuranceClaim do
  use Atlas.MCP.Tool,
    name: "attach_document_to_insurance_claim",
    schema: %{
      "type" => "object",
      "required" => ["claim_id", "document_id", "kind"],
      "properties" => %{
        "claim_id" => %{"type" => "string"},
        "document_id" => %{"type" => "string"},
        "kind" => %{
          "type" => "string",
          "enum" => Atlas.Insurance.ClaimDocument.kinds()
        },
        "notes" => %{"type" => "string"}
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "claim_id" => %{"type" => "string"},
        "document_id" => %{"type" => "string"},
        "kind" => %{"type" => "string"}
      },
      "required" => ["id", "claim_id", "document_id", "kind"],
      "additionalProperties" => false
    }

  alias Atlas.Insurance.Policies
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Attach an Atlas document to an insurance claim with a kind (photo, insurer_correspondence, repair_invoice, report, other). Executive only."
  end

  def execute(conn, %{"claim_id" => claim_id, "document_id" => document_id, "kind" => kind} = args) do
    with :ok <- Tool.authorize_scope(conn, "assets:write", "Hardware tools"),
         %_{} = claim <- Policies.get_claim(claim_id) do
      opts =
        case Map.get(args, "notes") do
          nil -> []
          value -> [notes: value]
        end

      case Policies.attach_document_to_claim(claim, document_id, kind, opts) do
        {:ok, link} ->
          {:ok, %{id: link.id, claim_id: link.claim_id, document_id: link.document_id, kind: link.kind}}

        {:error, :document_not_found} ->
          {:error, "Document not found."}

        {:error, changeset} ->
          {:error, "Could not attach document: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      nil -> {:error, "Insurance claim not found."}
    end
  end

  def execute(_conn, _args), do: {:error, "claim_id, document_id, and kind are required."}
end
