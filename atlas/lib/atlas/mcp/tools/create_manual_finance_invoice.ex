defmodule Atlas.MCP.Tools.CreateManualFinanceInvoice do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "create_manual_finance_invoice",
    schema: Atlas.MCP.Serializers.ManualFinanceInvoices.input_schema(:create),
    output_schema: Atlas.MCP.Serializers.ManualFinanceInvoices.response_schema()

  alias Atlas.Finance.Invoices
  alias Atlas.MCP.Serializers.ManualFinanceInvoices, as: Serializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description,
    do: "Record a manual vendor invoice for bookkeeping only. Never sends a payment or changes bank data."

  def execute(conn, args) do
    with :ok <- Tool.authorize_scope(conn, "finance:write", "Finance tools") do
      user = Tool.current_user(conn)
      Serializer.response(Invoices.create_manual_invoice(args, user, interface: "mcp"), user)
    end
  end
end
