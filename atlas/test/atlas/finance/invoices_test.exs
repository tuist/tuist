defmodule Atlas.Finance.InvoicesTest do
  use Atlas.DataCase, async: true

  import Atlas.FinanceFixtures

  alias Atlas.Finance

  describe "vendor_cost_analytics/1 settlement-date reconciliation" do
    test "buckets invoice spend by the linked transaction's settlement month, not the invoice date" do
      source = insert_finance_source!()
      account = insert_finance_account!(source)

      # Invoice dated in June, but the cash actually settled in July.
      transaction =
        insert_finance_transaction!(account, %{
          booked_at: ~U[2026-07-03 09:00:00Z],
          settled_at: ~U[2026-07-03 09:00:00Z],
          provider_updated_at: ~U[2026-07-03 09:00:00Z]
        })

      insert_finance_invoice!(%{
        invoice_date: ~D[2026-06-28],
        total_amount_value: Decimal.new("500.00"),
        total_amount_currency: "EUR",
        finance_transaction_id: transaction.id
      })

      analytics = Finance.vendor_cost_analytics(date_from: ~D[2026-07-01], date_to: ~D[2026-07-31])

      assert [%{date: ~D[2026-07-01], amount_value: amount}] = analytics.monthly_spend
      assert Decimal.equal?(amount, Decimal.new("500.00"))
    end

    test "falls back to the invoice date when no transaction is linked" do
      insert_finance_invoice!(%{
        invoice_date: ~D[2026-07-15],
        total_amount_value: Decimal.new("120.00"),
        total_amount_currency: "EUR"
      })

      analytics = Finance.vendor_cost_analytics(date_from: ~D[2026-07-01], date_to: ~D[2026-07-31])

      assert [%{date: ~D[2026-07-01], amount_value: amount}] = analytics.monthly_spend
      assert Decimal.equal?(amount, Decimal.new("120.00"))
    end

    test "excludes an invoice whose linked transaction settled outside the window even if its invoice date is inside" do
      source = insert_finance_source!()
      account = insert_finance_account!(source)

      # Invoice dated in July, but the cash settled in August — belongs to August.
      transaction =
        insert_finance_transaction!(account, %{
          booked_at: ~U[2026-08-02 09:00:00Z],
          settled_at: ~U[2026-08-02 09:00:00Z],
          provider_updated_at: ~U[2026-08-02 09:00:00Z]
        })

      insert_finance_invoice!(%{
        invoice_date: ~D[2026-07-30],
        total_amount_value: Decimal.new("750.00"),
        total_amount_currency: "EUR",
        finance_transaction_id: transaction.id
      })

      analytics = Finance.vendor_cost_analytics(date_from: ~D[2026-07-01], date_to: ~D[2026-07-31])

      assert analytics.monthly_spend == []
      assert analytics.invoice_count == 0
    end
  end
end
