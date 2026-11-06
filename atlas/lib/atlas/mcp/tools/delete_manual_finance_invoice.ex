defmodule Atlas.MCP.Tools.DeleteManualFinanceInvoice do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "delete_manual_finance_invoice",
    schema: %{
      "type" => "object",
      "required" => ["invoice_id"],
      "properties" => %{"invoice_id" => %{"type" => "string"}}
    },
    output_schema: %{
      "type" => "object",
      "required" => ["deleted"],
      "properties" => %{"deleted" => %{"type" => "boolean"}},
      "additionalProperties" => false
    }

  alias Atlas.Finance.Invoices
  alias Atlas.MCP.Serializers.ManualFinanceInvoices, as: Serializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description,
    do: "Delete a provenance-marked manual bookkeeping invoice. Never deletes imported invoices or bank data."

  def execute(conn, %{"invoice_id" => id}) do
    with :ok <- Tool.authorize_scope(conn, "finance:write", "Finance tools") do
      user = Tool.current_user(conn)

      case Invoices.delete_manual_invoice(id, user, interface: "mcp") do
        {:ok, _invoice} -> {:ok, %{deleted: true}}
        error -> Serializer.response(error, user)
      end
    end
  end
end
