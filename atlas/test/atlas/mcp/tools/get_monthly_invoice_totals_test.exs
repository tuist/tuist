defmodule Atlas.MCP.Tools.GetMonthlyInvoiceTotalsTest do
  use Atlas.MCP.ToolCase

  import Atlas.FinanceFixtures

  alias Atlas.MCP.Tools.GetMonthlyInvoiceTotals

  test "finance read and write can read whole-dataset original-currency invoice totals" do
    insert_finance_invoice!(%{invoice_date: ~D[2027-01-10], total_amount_value: Decimal.new("12.35")})
    insert_finance_invoice!(%{invoice_date: ~D[2027-01-31], total_amount_value: Decimal.new("7.20")})

    insert_finance_invoice!(%{
      invoice_date: ~D[2027-01-31],
      total_amount_value: Decimal.new("9.10"),
      total_amount_currency: "USD"
    })

    expected = [
      %{month: "2027-01", currency: "EUR", amount: "19.55"},
      %{month: "2027-01", currency: "USD", amount: "9.10"}
    ]

    for scope <- ["finance:read", "finance:write"] do
      assert {:ok, %{summary: ^expected}} =
               execute_tool(GetMonthlyInvoiceTotals, mcp_conn(insert_user!(%{scopes: [scope]})), %{})
    end

    assert {:error, _reason} = execute_tool(GetMonthlyInvoiceTotals, mcp_conn(insert_user!()), %{})
  end
end
