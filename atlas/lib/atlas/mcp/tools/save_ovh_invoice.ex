defmodule Atlas.MCP.Tools.SaveOVHInvoice do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "ovh_save_invoice",
    schema: %{
      "type" => "object",
      "required" => ["invoice_id"],
      "properties" => %{
        "invoice_id" => %{
          "type" => "string",
          "pattern" => "^[A-Za-z0-9_-]+$",
          "description" => "OVH bill ID from ovh_list_invoices or the billing email, e.g. INV_US1777493."
        }
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "required" => ["invoice_id", "date", "amount", "currency", "document_id", "filename", "content_type", "byte_size"],
      "properties" => %{
        "invoice_id" => %{"type" => "string"},
        "date" => %{"type" => "string"},
        "amount" => %{"type" => "string"},
        "currency" => %{"type" => "string"},
        "document_id" => %{"type" => "string"},
        "filename" => %{"type" => "string"},
        "content_type" => %{"type" => "string"},
        "byte_size" => %{"type" => "integer"}
      },
      "additionalProperties" => false
    }

  alias Atlas.Integrations.OVHInvoices
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.ManageAccountConnections

  @impl EMCP.Tool
  def description do
    "Retrieve an OVH US invoice PDF through your own ovh-orders connection and save it to the shared Atlas document library. " <>
      "Returns the total with tax in the invoice currency and a document_id for finance_add_transaction_attachment. " <>
      "Each successful call creates a document; reuse its ID rather than saving it again. Does not attach it to a transaction."
  end

  def execute(conn, %{"invoice_id" => invoice_id}) do
    with true <- ManageAccountConnections.allowed_context?(conn),
         :ok <- Tool.authorize_scope(conn, "finance:read", "OVH invoices"),
         :ok <- Tool.authorize_scope(conn, "documents:write", "Saving OVH invoices") do
      OVHInvoices.save(Tool.current_user(conn), invoice_id)
    else
      false -> {:error, "Personal OVH invoices are unavailable to shared Slack identities."}
      error -> error
    end
  end

  def execute(_conn, _args), do: {:error, "invoice_id is required."}
end
