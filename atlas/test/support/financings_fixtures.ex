defmodule Atlas.FinancingsFixtures do
  @moduledoc false

  alias Atlas.Finance.Financing
  alias Atlas.Finance.FinancingLine
  alias Atlas.Finance.FinancingPayment
  alias Atlas.Finance.FinancingSchedule
  alias Atlas.Repo

  def loan_attrs(attrs \\ %{}) do
    defaults = %{
      type: "loan",
      accounting_treatment: "undetermined",
      provider: "Test Bank",
      reference: "LOAN-#{System.unique_integer([:positive])}",
      disbursement_or_commencement_on: ~D[2026-01-15],
      term_months: 36,
      currency: "EUR",
      undiscounted_commitment: Decimal.new("36000.00"),
      principal_amount: Decimal.new("30000.00"),
      interest_rate: Decimal.new("0.0500")
    }

    Map.merge(defaults, attrs)
  end

  def lease_with_option_attrs(attrs \\ %{}) do
    defaults = %{
      type: "lease_with_purchase_option",
      accounting_treatment: "undetermined",
      provider: "Test Leasing",
      reference: "LEASE-#{System.unique_integer([:positive])}",
      disbursement_or_commencement_on: ~D[2026-02-01],
      term_months: 36,
      currency: "EUR",
      undiscounted_commitment: Decimal.new("18000.00"),
      purchase_option_amount: Decimal.new("500.00"),
      purchase_option_available_from: ~D[2029-02-01]
    }

    Map.merge(defaults, attrs)
  end

  def insert_financing!(attrs \\ %{}) do
    attrs =
      case Map.get(attrs, :type) do
        "loan" ->
          loan_attrs(attrs)

        "lease_with_purchase_option" ->
          lease_with_option_attrs(attrs)

        "lease_without_purchase_option" ->
          lease_with_option_attrs(attrs)
          |> Map.put(:type, "lease_without_purchase_option")
          |> Map.drop([:purchase_option_amount, :purchase_option_available_from])

        _ ->
          loan_attrs(attrs)
      end

    %Financing{}
    |> Financing.create_changeset(attrs)
    |> Repo.insert!()
  end

  def insert_schedule!(financing, attrs \\ %{}) do
    defaults = %{
      financing_id: financing.id,
      sequence: System.unique_integer([:positive]),
      due_on: ~D[2026-02-15],
      expected_total: Decimal.new("1000.00"),
      principal_amount: Decimal.new("900.00"),
      interest_amount: Decimal.new("100.00")
    }

    %FinancingSchedule{}
    |> FinancingSchedule.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  def insert_line!(financing, asset, share_bps \\ 10_000) do
    %FinancingLine{}
    |> FinancingLine.changeset(%{
      financing_id: financing.id,
      asset_id: asset.id,
      share_bps: share_bps
    })
    |> Repo.insert!()
  end

  def payment_attrs(financing, transaction, attrs \\ %{}) do
    defaults = %{
      financing_id: financing.id,
      finance_transaction_id: transaction.id,
      paid_on: ~D[2026-02-15],
      direction: transaction.direction,
      settlement_amount: transaction.amount_value,
      settlement_currency: transaction.amount_currency,
      resolution_status: "unresolved"
    }

    Map.merge(defaults, attrs)
  end

  def insert_payment!(financing, transaction, attrs \\ %{}) do
    %FinancingPayment{}
    |> FinancingPayment.changeset(payment_attrs(financing, transaction, attrs))
    |> Repo.insert!()
  end
end
