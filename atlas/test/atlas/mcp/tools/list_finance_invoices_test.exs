defmodule Atlas.MCP.Tools.ListFinanceInvoicesTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Finance.Invoice
  alias Atlas.Finance.InvoiceLineItem
  alias Atlas.MCP.Tools.ListFinanceInvoices
  alias Atlas.Repo

  test "lists extracted invoices with their line-item breakdown" do
    invoice = insert_finance_invoice!()
    insert_line_item!(invoice)

    assert {:ok, payload} = execute_tool(ListFinanceInvoices, executive_mcp_conn(), %{})

    assert payload.count == 1
    assert [serialized] = payload.invoices
    assert serialized.vendor_name == "Hetzner"
    assert serialized.total_amount_value == "120.50"
    assert serialized.document == nil
    assert serialized.transaction == nil

    assert [line_item] = serialized.line_items
    assert line_item.description == "Dedicated server"
    assert line_item.amount_value == "120.50"
    assert line_item.quantity == "1.0000"
    assert line_item.category == nil
  end

  test "requires an executive user" do
    assert {:error, message} = execute_tool(ListFinanceInvoices, nil, %{})
    assert message =~ "executive"
  end

  defp insert_finance_invoice!(attrs \\ %{}) do
    defaults = %{
      vendor_name: "Hetzner",
      invoice_number: "INV-#{System.unique_integer([:positive])}",
      invoice_date: ~D[2026-01-15],
      status: "extracted",
      total_amount_value: Decimal.new("120.50"),
      total_amount_currency: "EUR"
    }

    Repo.insert!(struct!(Invoice, Map.merge(defaults, attrs)))
  end

  defp insert_line_item!(invoice, attrs \\ %{}) do
    defaults = %{
      finance_invoice_id: invoice.id,
      description: "Dedicated server",
      amount_value: Decimal.new("120.50"),
      amount_currency: "EUR",
      quantity: Decimal.new("1")
    }

    Repo.insert!(struct!(InvoiceLineItem, Map.merge(defaults, attrs)))
  end
end
