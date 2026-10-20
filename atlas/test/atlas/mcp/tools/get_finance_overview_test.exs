defmodule Atlas.MCP.Tools.GetFinanceOverviewTest do
  use Atlas.MCP.ToolCase

  import Atlas.FinanceFixtures

  alias Atlas.MCP.Tools.GetFinanceOverview

  test "returns treasury metrics and source sync state" do
    conn = executive_mcp_conn()
    debit_at = days_ago(28)
    credit_at = days_ago(26)

    company =
      insert_account!(%{
        name: "Tuist GmbH",
        segment: :customer,
        status: "active",
        currency: "EUR",
        current_value: Decimal.new("240.00"),
        next_renewal_date: ~D[2027-01-01]
      })

    source =
      insert_finance_source!(%{
        atlas_account_id: company.id,
        provider: "qonto",
        config_key: "qonto-main",
        name: "Qonto Main",
        last_successful_sync_at: ~U[2026-05-26 08:00:00Z]
      })

    account =
      insert_finance_account!(source, %{
        name: "Operating",
        balance_value: Decimal.new("1000.00"),
        available_balance_value: Decimal.new("900.00")
      })

    insert_finance_transaction!(account, %{
      external_id: "txn-debit",
      direction: "debit",
      amount_value: Decimal.new("120.00"),
      booked_at: debit_at,
      settled_at: debit_at,
      provider_updated_at: debit_at
    })

    insert_finance_transaction!(account, %{
      external_id: "txn-credit",
      direction: "credit",
      amount_value: Decimal.new("30.00"),
      kind: "invoice_payment",
      booked_at: credit_at,
      settled_at: credit_at,
      provider_updated_at: credit_at
    })

    {:ok, payload} = execute_tool(GetFinanceOverview, conn, %{})

    assert payload.source_count == 1

    assert payload.sources == [
             %{
               atlas_account: %{
                 account_key: company.account_key,
                 id: company.id,
                 name: "Tuist GmbH"
               },
               config_key: source.config_key,
               external_id: nil,
               id: source.id,
               last_error: nil,
               last_successful_sync_at: "2026-05-26T08:00:00Z",
               last_synced_at: nil,
               metadata: %{},
               name: "Qonto Main",
               provider: "qonto"
             }
           ]

    assert payload.overview.currency == "EUR"
    assert payload.overview.available_cash_value == "900.00"
    assert payload.overview.total_balance_value == "1000.00"
    assert payload.overview.transaction_count_30d == 2
    assert Decimal.equal?(Decimal.new(payload.overview.net_30d_value), Decimal.new("-90.00"))
    assert Decimal.equal?(Decimal.new(payload.overview.monthly_burn_value), Decimal.new("15.00"))
    assert Decimal.equal?(Decimal.new(payload.overview.smoothed_monthly_burn_value), Decimal.new("15.00"))
    assert Decimal.equal?(Decimal.new(payload.overview.runway_months), Decimal.new("60.00"))
    assert Decimal.equal?(Decimal.new(payload.overview.trailing_cash_runway_months), Decimal.new("60.00"))
    assert Decimal.equal?(Decimal.new(payload.overview.smoothed_cash_runway_months), Decimal.new("60.00"))
    assert Decimal.equal?(Decimal.new(payload.overview.plan_adjusted_monthly_burn_value), Decimal.new("0"))
    assert is_nil(payload.overview.plan_adjusted_runway_months)
  end

  test "rejects non-executive users" do
    conn =
      %{role: :employee}
      |> insert_user!()
      |> mcp_conn()

    assert {:error, "Finance tools require the finance:read scope."} =
             execute_tool(GetFinanceOverview, conn, %{})
  end

  defp days_ago(days) do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.add(-days * 24 * 60 * 60, :second)
  end
end
