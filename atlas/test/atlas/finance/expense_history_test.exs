defmodule Atlas.Finance.ExpenseHistoryTest do
  use Atlas.DataCase, async: true

  import Atlas.FinanceFixtures

  alias Atlas.Finance.ExpenseHistory

  test "builds a three-month calendar history with a partial current month" do
    source = insert_finance_source!()
    account = insert_finance_account!(source)
    category = insert_finance_category!(%{name: "Cloud Infrastructure", direction: "debit"})

    insert_finance_transaction!(account, %{
      settled_at: ~U[2026-06-15 12:00:00Z],
      amount_value: Decimal.new("1200.00"),
      finance_category_id: category.id
    })

    insert_finance_transaction!(account, %{
      settled_at: ~U[2026-07-15 12:00:00Z],
      amount_value: Decimal.new("2400.00")
    })

    insert_finance_transaction!(account, %{
      settled_at: ~U[2026-08-20 12:00:00Z],
      amount_value: Decimal.new("1800.00")
    })

    insert_finance_transaction!(account, %{
      settled_at: ~U[2026-08-21 12:00:00Z],
      amount_value: Decimal.new("500.00"),
      affects_runway: false
    })

    history = ExpenseHistory.build(ending_on: ~D[2026-08-24], months: 3, currency: "EUR")

    assert history.currency == "EUR"
    assert [june, july, august] = history.months

    assert june.period == %{date_from: ~D[2026-06-01], date_to: ~D[2026-06-30], partial?: false}
    assert Decimal.equal?(june.total_amount_value, Decimal.new("1200.00"))
    assert june.complete?
    assert %{name: "Cloud Infrastructure", total_amount_value: amount} = List.first(june.categories)
    assert Decimal.equal?(amount, Decimal.new("1200.00"))

    assert Decimal.equal?(july.total_amount_value, Decimal.new("2400.00"))
    assert august.period == %{date_from: ~D[2026-08-01], date_to: ~D[2026-08-24], partial?: true}
    assert Decimal.equal?(august.total_amount_value, Decimal.new("1800.00"))
    assert august.matching_debit_transaction_count == 2
    assert august.included_transaction_count == 1
    assert august.exclusions.non_expense_transaction_count == 1
  end
end
