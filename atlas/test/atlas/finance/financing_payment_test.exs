defmodule Atlas.Finance.FinancingPaymentTest do
  use Atlas.DataCase, async: true

  import Atlas.FinanceFixtures
  import Atlas.FinancingsFixtures

  alias Atlas.Finance.FinancingPayment
  alias Atlas.Repo

  setup do
    source = insert_finance_source!()
    account = insert_finance_account!(source)
    financing = insert_financing!()

    txn =
      insert_finance_transaction!(account, %{
        amount_value: Decimal.new("1000.00"),
        amount_currency: "EUR"
      })

    %{financing: financing, transaction: txn}
  end

  test "insert with a full resolved decomposition", %{financing: financing, transaction: txn} do
    attrs =
      payment_attrs(financing, txn, %{
        resolution_status: "resolved",
        principal_amount: Decimal.new("900.00"),
        interest_amount: Decimal.new("100.00")
      })

    assert {:ok, payment} =
             %FinancingPayment{}
             |> FinancingPayment.changeset(attrs)
             |> Repo.insert()

    assert payment.resolution_status == "resolved"
  end

  test "rejects resolved payment whose components do not sum to settlement", %{
    financing: financing,
    transaction: txn
  } do
    attrs =
      payment_attrs(financing, txn, %{
        resolution_status: "resolved",
        principal_amount: Decimal.new("800.00")
      })

    assert {:error, changeset} =
             %FinancingPayment{}
             |> FinancingPayment.changeset(attrs)
             |> Repo.insert()

    assert errors_on(changeset)[:resolution_status]
  end

  test "rejects resolved payment with unclassified > 0", %{
    financing: financing,
    transaction: txn
  } do
    attrs =
      payment_attrs(financing, txn, %{
        resolution_status: "resolved",
        principal_amount: Decimal.new("900.00"),
        interest_amount: Decimal.new("50.00"),
        unclassified_amount: Decimal.new("50.00")
      })

    assert {:error, changeset} =
             %FinancingPayment{}
             |> FinancingPayment.changeset(attrs)
             |> Repo.insert()

    assert errors_on(changeset)[:unclassified_amount]
  end

  test "rejects any payment whose components exceed settlement", %{
    financing: financing,
    transaction: txn
  } do
    attrs =
      payment_attrs(financing, txn, %{
        resolution_status: "partial",
        principal_amount: Decimal.new("1500.00")
      })

    assert {:error, changeset} =
             %FinancingPayment{}
             |> FinancingPayment.changeset(attrs)
             |> Repo.insert()

    assert errors_on(changeset)[:settlement_amount]
  end

  test "allows a partial payment with a positive unclassified amount", %{
    financing: financing,
    transaction: txn
  } do
    attrs =
      payment_attrs(financing, txn, %{
        resolution_status: "partial",
        unclassified_amount: Decimal.new("500.00")
      })

    assert {:ok, %FinancingPayment{resolution_status: "partial"}} =
             %FinancingPayment{}
             |> FinancingPayment.changeset(attrs)
             |> Repo.insert()
  end

  test "rejects two payments matching the same transaction", %{
    financing: financing,
    transaction: txn
  } do
    _ = insert_payment!(financing, txn)

    {:error, changeset} =
      %FinancingPayment{}
      |> FinancingPayment.changeset(payment_attrs(financing, txn))
      |> Repo.insert()

    assert errors_on(changeset)[:finance_transaction_id] == ["has already been taken"]
  end
end
