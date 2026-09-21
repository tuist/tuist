defmodule Atlas.MCP.Tools.DetachDocumentFromInsurancePolicy do
  use Atlas.MCP.Tool,
    name: "detach_document_from_insurance_policy",
    schema: %{
      "type" => "object",
      "required" => ["link_id"],
      "properties" => %{"link_id" => %{"type" => "string"}},
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"deleted" => %{"type" => "boolean"}},
      "required" => ["deleted"],
      "additionalProperties" => false
    }

  alias Atlas.Insurance.Policies
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Remove a document from an insurance policy (does not delete the underlying Atlas document). Executive only."
  end

  def execute(conn, %{"link_id" => id}) do
    with :ok <- Tool.authorize_scope(conn, "assets:write", "Hardware tools") do
      case Policies.detach_document_from_policy(id) do
        {:ok, _} -> {:ok, %{deleted: true}}
        {:error, :not_found} -> {:error, "Attachment not found."}
        {:error, changeset} -> {:error, "Could not detach document: #{Tool.format_changeset_errors(changeset)}"}
      end
    end
  end

  def execute(_conn, _args), do: {:error, "link_id is required."}
end
