defmodule Atlas.MCP.Tools.GetFinanceExpenseHistoryTest do
  use Atlas.MCP.ToolCase

  import Atlas.FinanceFixtures

  alias Atlas.MCP.Tools.GetFinanceExpenseHistory

  test "returns exact monthly cash-expense history" do
    source = insert_finance_source!()
    account = insert_finance_account!(source)

    insert_finance_transaction!(account, %{
      settled_at: ~U[2026-06-15 12:00:00Z],
      amount_value: Decimal.new("1200.00")
    })

    insert_finance_transaction!(account, %{
      settled_at: ~U[2026-07-15 12:00:00Z],
      amount_value: Decimal.new("2400.00")
    })

    insert_finance_transaction!(account, %{
      settled_at: ~U[2026-08-20 12:00:00Z],
      amount_value: Decimal.new("1800.00")
    })

    assert {:ok, payload} =
             execute_tool(GetFinanceExpenseHistory, executive_mcp_conn(), %{
               "ending_on" => "2026-08-24",
               "months" => 3
             })

    assert payload.currency == "EUR"

    assert payload.months == [
             %{
               date_from: "2026-06-01",
               date_to: "2026-06-30",
               partial: false,
               total_amount_value: "1200.00",
               included_transaction_count: 1,
               matching_debit_transaction_count: 1,
               complete: true,
               categories: [%{name: "Uncategorized", total_amount_value: "1200.00", transaction_count: 1}],
               exclusions: %{
                 non_expense_transaction_count: 0,
                 unconverted_currencies: [],
                 unconverted_transaction_count: 0
               }
             },
             %{
               date_from: "2026-07-01",
               date_to: "2026-07-31",
               partial: false,
               total_amount_value: "2400.00",
               included_transaction_count: 1,
               matching_debit_transaction_count: 1,
               complete: true,
               categories: [%{name: "Uncategorized", total_amount_value: "2400.00", transaction_count: 1}],
               exclusions: %{
                 non_expense_transaction_count: 0,
                 unconverted_currencies: [],
                 unconverted_transaction_count: 0
               }
             },
             %{
               date_from: "2026-08-01",
               date_to: "2026-08-24",
               partial: true,
               total_amount_value: "1800.00",
               included_transaction_count: 1,
               matching_debit_transaction_count: 1,
               complete: true,
               categories: [%{name: "Uncategorized", total_amount_value: "1800.00", transaction_count: 1}],
               exclusions: %{
                 non_expense_transaction_count: 0,
                 unconverted_currencies: [],
                 unconverted_transaction_count: 0
               }
             }
           ]
  end

  test "rejects an invalid history length" do
    assert {:error, "months must be an integer between 1 and 12."} =
             execute_tool(GetFinanceExpenseHistory, executive_mcp_conn(), %{
               "ending_on" => "2026-08-24",
               "months" => 13
             })
  end
end
