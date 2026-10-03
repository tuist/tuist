defmodule Atlas.MCP.Tools.ListFinanceTransactionsTest do
  use Atlas.MCP.ToolCase

  import Atlas.FinanceFixtures

  alias Atlas.MCP.Tools.ListFinanceTransactions

  test "filters finance transactions by source, direction, currency, date range, and query" do
    conn = executive_mcp_conn()
    tuist_gmbh = insert_account!(%{name: "Tuist GmbH", segment: :customer})
    tuist_inc = insert_account!(%{name: "Tuist Inc.", segment: :customer})

    qonto_source =
      insert_finance_source!(%{
        atlas_account_id: tuist_gmbh.id,
        provider: "qonto",
        config_key: "qonto-main",
        name: "Qonto Main"
      })

    mercury_source =
      insert_finance_source!(%{
        atlas_account_id: tuist_inc.id,
        provider: "mercury",
        config_key: "mercury-main",
        name: "Mercury Main"
      })

    qonto_account = insert_finance_account!(qonto_source, %{name: "Operating", currency: "EUR"})
    mercury_account = insert_finance_account!(mercury_source, %{name: "Reserve", currency: "USD"})
    category = insert_finance_category!(%{name: "Payroll", direction: "debit"})

    payroll =
      insert_finance_transaction!(qonto_account, %{
        external_id: "txn-payroll",
        finance_category_id: category.id,
        categorized_at: ~U[2026-05-20 10:00:00Z],
        categorization_confidence: Decimal.new("0.95"),
        categorization_reason: "Payroll provider",
        categorized_by_agent: "finance_transaction_categorization_agent",
        direction: "debit",
        status: "completed",
        kind: "salary",
        counterparty_name: "Payroll Provider",
        description: "Monthly payroll",
        amount_value: Decimal.new("2500.00"),
        amount_currency: "EUR",
        booked_at: ~U[2026-05-20 09:00:00Z],
        settled_at: ~U[2026-05-20 09:00:00Z],
        provider_updated_at: ~U[2026-05-20 09:00:00Z]
      })

    _interest =
      insert_finance_transaction!(mercury_account, %{
        external_id: "txn-interest",
        direction: "credit",
        status: "completed",
        kind: "interest",
        counterparty_name: "Mercury",
        description: "Balance interest",
        amount_value: Decimal.new("45.00"),
        amount_currency: "USD",
        booked_at: ~U[2026-05-15 09:00:00Z],
        settled_at: ~U[2026-05-15 09:00:00Z],
        provider_updated_at: ~U[2026-05-15 09:00:00Z]
      })

    {:ok, payload} =
      execute_tool(ListFinanceTransactions, conn, %{
        "source_key" => qonto_source.config_key,
        "atlas_account_key" => tuist_gmbh.account_key,
        "direction" => "debit",
        "currency" => "EUR",
        "category_id" => category.id,
        "category_slug" => category.slug,
        "date_from" => "2026-05-01",
        "date_to" => "2026-05-31",
        "query" => "payroll"
      })

    assert payload.count == 1
    qonto_source_key = qonto_source.config_key
    category_slug = category.slug
    tuist_gmbh_key = tuist_gmbh.account_key

    assert [
             %{
               account: %{
                 atlas_account: %{account_key: ^tuist_gmbh_key},
                 source_key: ^qonto_source_key
               },
               counterparty_name: "Payroll Provider",
               direction: "debit",
               kind: "salary",
               category: %{name: "Payroll", slug: ^category_slug},
               categorization_confidence: "0.9500",
               categorization_reason: "Payroll provider",
               categorized_by_agent: "finance_transaction_categorization_agent",
               amount_value: "2500.00",
               amount_currency: "EUR"
             }
           ] = payload.transactions

    assert hd(payload.transactions).id == payroll.id
    assert hd(payload.transactions).account.id == qonto_account.id
  end

  test "respects page_size and reverse chronological ordering" do
    conn = executive_mcp_conn()
    source = insert_finance_source!(%{config_key: "qonto-main"})
    account = insert_finance_account!(source)

    _older =
      insert_finance_transaction!(account, %{
        external_id: "txn-older",
        booked_at: ~U[2026-05-01 09:00:00Z],
        settled_at: ~U[2026-05-01 09:00:00Z],
        provider_updated_at: ~U[2026-05-01 09:00:00Z]
      })

    newer =
      insert_finance_transaction!(account, %{
        external_id: "txn-newer",
        booked_at: ~U[2026-05-21 09:00:00Z],
        settled_at: ~U[2026-05-21 09:00:00Z],
        provider_updated_at: ~U[2026-05-21 09:00:00Z]
      })

    {:ok, payload} = execute_tool(ListFinanceTransactions, conn, %{"page_size" => 1})

    assert payload.count == 1
    assert hd(payload.transactions).id == newer.id
  end

  test "rejects non-executive users" do
    conn =
      %{role: :employee}
      |> insert_user!()
      |> mcp_conn()

    assert {:error, "Finance tools require the finance:read scope."} =
             execute_tool(ListFinanceTransactions, conn, %{})
  end
end
