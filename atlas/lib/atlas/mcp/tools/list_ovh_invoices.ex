defmodule Atlas.MCP.Tools.ListOVHInvoices do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "ovh_list_invoices",
    schema: %{
      "type" => "object",
      "properties" => %{
        "date_from" => %{"type" => "string", "description" => "Inclusive lower bound, e.g. 2026-11-01T00:00:00Z."},
        "date_to" => %{"type" => "string", "description" => "Inclusive upper bound, e.g. 2026-11-30T23:59:59Z."}
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "required" => ["invoice_ids"],
      "properties" => %{"invoice_ids" => %{"type" => "array", "items" => %{"type" => "string"}}},
      "additionalProperties" => false
    }

  alias Atlas.Integrations.OVHInvoices
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.ManageAccountConnections

  @impl EMCP.Tool
  def description do
    "List OVH US invoice IDs through your own ovh-orders connection, optionally filtered by invoice datetime. " <>
      "Omitting dates lists all invoices. Use ovh_save_invoice with an invoice_id to retrieve its PDF into Atlas."
  end

  def execute(conn, args) do
    with true <- ManageAccountConnections.allowed_context?(conn),
         :ok <- Tool.authorize_scope(conn, "finance:read", "OVH invoices") do
      OVHInvoices.list(Tool.current_user(conn), args)
    else
      false -> {:error, "Personal OVH invoices are unavailable to shared Slack identities."}
      error -> error
    end
  end
end
