defmodule Atlas.MCP.Tools.UpdateManualFinanceInvoice do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "update_manual_finance_invoice",
    schema: Atlas.MCP.Serializers.ManualFinanceInvoices.input_schema(:update),
    output_schema: Atlas.MCP.Serializers.ManualFinanceInvoices.response_schema()

  alias Atlas.Finance.Invoices
  alias Atlas.MCP.Serializers.ManualFinanceInvoices, as: Serializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description,
    do: "Edit a provenance-marked manual vendor invoice. Imported and transaction-linked entries are read-only."

  def execute(conn, %{"invoice_id" => id} = args) do
    with :ok <- Tool.authorize_scope(conn, "finance:write", "Finance tools") do
      user = Tool.current_user(conn)
      Serializer.response(Invoices.update_manual_invoice(id, args, user, interface: "mcp"), user)
    end
  end
end
