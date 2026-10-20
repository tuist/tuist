defmodule Atlas.MCP.Tools.GetFinanceExpenseReconciliationTest do
  use Atlas.MCP.ToolCase

  import Atlas.FinanceFixtures

  alias Atlas.MCP.Tools.GetFinanceExpenseReconciliation

  test "reconciles every cash expense across accounts without a result limit" do
    conn = executive_mcp_conn()
    qonto_source = insert_finance_source!(%{provider: "qonto", config_key: "qonto-main", name: "Qonto Main"})
    mercury_source = insert_finance_source!(%{provider: "mercury", config_key: "mercury-main", name: "Mercury Main"})
    qonto_account = insert_finance_account!(qonto_source, %{name: "Hauptkonto", currency: "EUR"})
    mercury_account = insert_finance_account!(mercury_source, %{name: "US Operating", currency: "USD"})
    category = insert_finance_category!(%{name: "Cloud Infrastructure", direction: "debit"})

    insert_finance_transaction!(qonto_account, %{
      external_id: "clickhouse",
      direction: "debit",
      amount_value: Decimal.new("2690.68"),
      amount_currency: "EUR",
      finance_category_id: category.id,
      settled_at: ~U[2026-07-30 10:18:00Z]
    })

    insert_finance_transaction!(qonto_account, %{
      external_id: "rent",
      direction: "debit",
      amount_value: Decimal.new("900.00"),
      amount_currency: "EUR",
      settled_at: ~U[2026-07-01 10:18:00Z]
    })

    insert_finance_transaction!(mercury_account, %{
      external_id: "internal-transfer",
      direction: "debit",
      amount_value: Decimal.new("100.00"),
      amount_currency: "USD",
      affects_runway: false,
      settled_at: ~U[2026-07-15 10:18:00Z]
    })

    {:ok, payload} =
      execute_tool(GetFinanceExpenseReconciliation, conn, %{"date_from" => "2026-07-01", "date_to" => "2026-07-31"})

    assert payload.currency == "EUR"
    assert payload.total_amount_value == "3590.68"
    assert payload.included_transaction_count == 2
    assert payload.matching_debit_transaction_count == 3
    assert payload.complete
    assert payload.exclusions.non_expense_transaction_count == 1
    assert payload.exclusions.unconverted_transaction_count == 0

    assert %{name: "Cloud Infrastructure", transaction_count: 1, total_amount_value: "2690.68"} in payload.categories
    assert %{name: "Uncategorized", transaction_count: 1, total_amount_value: "900.00"} in payload.categories
    assert Enum.any?(payload.accounts, &(&1.id == qonto_account.id and &1.matching_expense_transaction_count == 2))
    assert Enum.any?(payload.accounts, &(&1.id == mercury_account.id and &1.matching_expense_transaction_count == 0))
  end

  test "rejects an invalid reconciliation period" do
    assert {:error, "date_from must be on or before date_to."} =
             execute_tool(GetFinanceExpenseReconciliation, executive_mcp_conn(), %{
               "date_from" => "2026-08-01",
               "date_to" => "2026-07-31"
             })
  end
end
