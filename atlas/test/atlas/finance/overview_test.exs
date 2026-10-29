defmodule Atlas.Finance.OverviewTest do
  use Atlas.DataCase, async: true

  import Atlas.FinanceFixtures

  alias Atlas.Accounts.Account
  alias Atlas.Finance.Overview
  alias Atlas.Repo

  test "builds available cash, burn, runway, and sync freshness from normalized data" do
    source =
      insert_finance_source!(%{
        provider: "qonto",
        config_key: "qonto-main",
        name: "Qonto Main",
        last_successful_sync_at: ~U[2026-05-26 08:00:00Z]
      })

    account =
      insert_finance_account!(source, %{
        available_balance_value: Decimal.new("900.00"),
        balance_value: Decimal.new("1000.00")
      })

    insert_finance_transaction!(account, %{
      external_id: "txn-payroll",
      direction: "debit",
      amount_value: Decimal.new("120.00"),
      booked_at: ~U[2026-05-20 09:00:00Z],
      settled_at: ~U[2026-05-20 09:00:00Z],
      provider_updated_at: ~U[2026-05-20 09:00:00Z]
    })

    insert_finance_transaction!(account, %{
      external_id: "txn-invoice",
      direction: "credit",
      amount_value: Decimal.new("30.00"),
      booked_at: ~U[2026-05-12 09:00:00Z],
      settled_at: ~U[2026-05-12 09:00:00Z],
      provider_updated_at: ~U[2026-05-12 09:00:00Z]
    })

    %Account{}
    |> Account.changeset(%{
      account_key: "customer:northstar",
      name: "Northstar",
      segment: :customer,
      status: "active",
      currency: "EUR",
      current_value: Decimal.new("240.00"),
      next_renewal_date: ~D[2027-01-01]
    })
    |> Repo.insert!()

    overview = Overview.build(now: ~U[2026-05-26 12:00:00Z])

    assert overview.currency == "EUR"
    assert Decimal.equal?(overview.available_cash_value, Decimal.new("900.00"))
    assert Decimal.equal?(overview.total_balance_value, Decimal.new("1000.00"))
    assert Decimal.equal?(overview.net_30d_value, Decimal.new("-90.00"))
    assert Decimal.equal?(overview.monthly_burn_value, Decimal.new("15.00"))
    assert Decimal.equal?(overview.smoothed_monthly_burn_value, Decimal.new("15.00"))
    assert Decimal.equal?(overview.runway_months, Decimal.new("60.00"))
    assert Decimal.equal?(overview.trailing_cash_runway_months, Decimal.new("60.00"))
    assert Decimal.equal?(overview.smoothed_cash_runway_months, Decimal.new("60.00"))
    assert Decimal.equal?(overview.projected_monthly_revenue_value, Decimal.new("20.00"))
    assert Decimal.equal?(overview.projected_arr_value, Decimal.new("240.00"))
    assert overview.projected_customer_count == 1
    assert Decimal.equal?(overview.projected_monthly_expenses_value, Decimal.new("20.00"))
    assert Decimal.equal?(overview.projected_net_burn_value, Decimal.new("0"))
    assert is_nil(overview.projected_runway_months)
    assert Decimal.equal?(overview.plan_adjusted_monthly_burn_value, Decimal.new("0"))
    assert is_nil(overview.plan_adjusted_runway_months)
    assert overview.account_count == 1
    assert overview.source_count == 1
    assert overview.transaction_count_30d == 2
    assert overview.last_synced_at == ~U[2026-05-26 08:00:00Z]
  end

  test "converts mixed account and transaction currencies into report currency" do
    source =
      insert_finance_source!(%{
        provider: "mercury",
        config_key: "mercury",
        name: "Mercury"
      })

    eur_account =
      insert_finance_account!(source, %{
        external_id: "eur-account",
        currency: "EUR",
        balance_value: Decimal.new("1000.00"),
        balance_currency: "EUR",
        available_balance_value: Decimal.new("900.00"),
        available_balance_currency: "EUR"
      })

    usd_account =
      insert_finance_account!(source, %{
        external_id: "usd-account",
        currency: "USD",
        balance_value: Decimal.new("117.02"),
        balance_currency: "USD",
        available_balance_value: Decimal.new("117.02"),
        available_balance_currency: "USD"
      })

    insert_finance_transaction!(eur_account, %{
      external_id: "eur-debit",
      direction: "debit",
      amount_value: Decimal.new("30.00"),
      amount_currency: "EUR",
      booked_at: ~U[2026-05-20 09:00:00Z],
      settled_at: ~U[2026-05-20 09:00:00Z],
      provider_updated_at: ~U[2026-05-20 09:00:00Z]
    })

    insert_finance_transaction!(usd_account, %{
      external_id: "usd-debit",
      direction: "debit",
      amount_value: Decimal.new("117.02"),
      amount_currency: "USD",
      booked_at: ~U[2026-05-20 09:00:00Z],
      settled_at: ~U[2026-05-20 09:00:00Z],
      provider_updated_at: ~U[2026-05-20 09:00:00Z]
    })

    overview = Overview.build(now: ~U[2026-05-26 12:00:00Z])

    assert Decimal.equal?(Decimal.round(overview.available_cash_value, 2), Decimal.new("1000.00"))
    assert Decimal.equal?(Decimal.round(overview.total_balance_value, 2), Decimal.new("1100.00"))
    assert Decimal.equal?(Decimal.round(overview.net_30d_value, 2), Decimal.new("-130.00"))
    assert Decimal.equal?(Decimal.round(overview.monthly_burn_value, 2), Decimal.new("21.67"))
  end

  test "uses affected runway transactions regardless of provider status" do
    source =
      insert_finance_source!(%{
        provider: "mercury",
        config_key: "mercury",
        name: "Mercury"
      })

    account = insert_finance_account!(source)

    insert_finance_transaction!(account, %{
      external_id: "mercury-sent-debit",
      provider: "mercury",
      status: "sent",
      direction: "debit",
      amount_value: Decimal.new("90.00"),
      booked_at: ~U[2026-05-20 09:00:00Z],
      settled_at: ~U[2026-05-20 09:00:00Z],
      provider_updated_at: ~U[2026-05-20 09:00:00Z],
      affects_runway: true
    })

    insert_finance_transaction!(account, %{
      external_id: "mercury-pending-debit",
      provider: "mercury",
      status: "pending",
      direction: "debit",
      amount_value: Decimal.new("900.00"),
      booked_at: ~U[2026-05-20 09:00:00Z],
      settled_at: ~U[2026-05-20 09:00:00Z],
      provider_updated_at: ~U[2026-05-20 09:00:00Z],
      affects_runway: false
    })

    overview = Overview.build(now: ~U[2026-05-26 12:00:00Z])

    assert overview.transaction_count_30d == 1
    assert Decimal.equal?(overview.net_30d_value, Decimal.new("-90.00"))
    assert Decimal.equal?(overview.monthly_burn_value, Decimal.new("15.00"))
  end

  test "excludes internal transfer kinds from runway metrics" do
    source = insert_finance_source!(%{provider: "mercury", config_key: "mercury", name: "Mercury"})
    account = insert_finance_account!(source)

    insert_finance_transaction!(account, %{
      external_id: "mercury-reserve-transfer",
      provider: "mercury",
      status: "sent",
      direction: "debit",
      kind: "internal_transfer",
      counterparty_name: "Mercury Reserve",
      amount_value: Decimal.new("900.00"),
      booked_at: ~U[2026-05-20 09:00:00Z],
      settled_at: ~U[2026-05-20 09:00:00Z],
      provider_updated_at: ~U[2026-05-20 09:00:00Z],
      affects_runway: true
    })

    overview = Overview.build(now: ~U[2026-05-26 12:00:00Z])

    assert overview.transaction_count_30d == 0
    assert Decimal.equal?(overview.net_30d_value, Decimal.new("0"))
    assert Decimal.equal?(overview.monthly_burn_value, Decimal.new("0"))
    assert is_nil(overview.runway_months)
  end

  test "keeps external transfer kinds when they affect runway" do
    source = insert_finance_source!(%{provider: "mercury", config_key: "mercury", name: "Mercury"})
    account = insert_finance_account!(source, %{available_balance_value: Decimal.new("900.00")})

    insert_finance_transaction!(account, %{
      external_id: "mercury-vendor-transfer",
      provider: "mercury",
      status: "sent",
      direction: "debit",
      kind: "external_transfer",
      counterparty_name: "Vendor",
      amount_value: Decimal.new("90.00"),
      booked_at: ~U[2026-05-20 09:00:00Z],
      settled_at: ~U[2026-05-20 09:00:00Z],
      provider_updated_at: ~U[2026-05-20 09:00:00Z],
      affects_runway: true
    })

    overview = Overview.build(now: ~U[2026-05-26 12:00:00Z])

    assert overview.transaction_count_30d == 1
    assert Decimal.equal?(overview.net_30d_value, Decimal.new("-90.00"))
    assert Decimal.equal?(overview.monthly_burn_value, Decimal.new("15.00"))
    assert Decimal.equal?(overview.runway_months, Decimal.new("60.00"))
  end

  test "computes EOY committed pipeline" do
    source =
      insert_finance_source!(%{
        provider: "qonto",
        config_key: "qonto-main",
        name: "Qonto Main"
      })

    account =
      insert_finance_account!(source, %{
        available_balance_value: Decimal.new("900.00"),
        balance_value: Decimal.new("1000.00")
      })

    insert_finance_transaction!(account, %{
      external_id: "txn-payroll",
      direction: "debit",
      amount_value: Decimal.new("120.00"),
      booked_at: ~U[2026-05-20 09:00:00Z],
      settled_at: ~U[2026-05-20 09:00:00Z],
      provider_updated_at: ~U[2026-05-20 09:00:00Z]
    })

    %Account{}
    |> Account.changeset(%{
      account_key: "customer:inside-eoy",
      name: "Inside EOY",
      segment: :customer,
      status: "active",
      currency: "EUR",
      current_value: Decimal.new("120.00"),
      next_renewal_date: ~D[2026-09-15]
    })
    |> Repo.insert!()

    %Account{}
    |> Account.changeset(%{
      account_key: "customer:outside-eoy",
      name: "Outside EOY",
      segment: :customer,
      status: "active",
      currency: "EUR",
      current_value: Decimal.new("240.00"),
      next_renewal_date: ~D[2027-03-01]
    })
    |> Repo.insert!()

    %Account{}
    |> Account.changeset(%{
      account_key: "customer:paused",
      name: "Paused Co",
      segment: :customer,
      status: "paused",
      currency: "EUR",
      current_value: Decimal.new("999.00"),
      next_renewal_date: ~D[2026-10-15]
    })
    |> Repo.insert!()

    overview = Overview.build(now: ~U[2026-05-26 12:00:00Z])

    assert overview.committed_pipeline_count == 1
    assert Decimal.equal?(overview.committed_pipeline_value, Decimal.new("120.00"))
    assert overview.next_committed_renewal == %{name: "Inside EOY", renewal_date: ~D[2026-09-15]}
    assert overview.committed_pipeline_horizon == ~D[2026-12-31]

    # Cash + committed / projected_net_burn. Revenue exceeds expenses so projected_net_burn is 0 → nil.
    assert is_nil(overview.cash_plus_committed_runway_months)
  end

  test "runway_uplift_months bridges cash-only and plan-adjusted runway" do
    source = insert_finance_source!(%{provider: "qonto", config_key: "qonto-main", name: "Qonto Main"})

    account =
      insert_finance_account!(source, %{
        available_balance_value: Decimal.new("900.00"),
        balance_value: Decimal.new("1000.00")
      })

    insert_finance_transaction!(account, %{
      external_id: "txn-debit",
      direction: "debit",
      amount_value: Decimal.new("180.00"),
      booked_at: ~U[2026-05-20 09:00:00Z],
      settled_at: ~U[2026-05-20 09:00:00Z],
      provider_updated_at: ~U[2026-05-20 09:00:00Z]
    })

    %Account{}
    |> Account.changeset(%{
      account_key: "customer:bridge",
      name: "Bridge Co",
      segment: :customer,
      status: "active",
      currency: "EUR",
      current_value: Decimal.new("120.00"),
      next_renewal_date: ~D[2026-09-15]
    })
    |> Repo.insert!()

    overview = Overview.build(now: ~U[2026-05-26 12:00:00Z])

    # plan_adjusted_runway_months > runway_months because revenue trims the burn.
    assert Decimal.gt?(overview.runway_uplift_months, Decimal.new("0"))

    assert Decimal.equal?(
             overview.runway_uplift_months,
             Decimal.sub(overview.plan_adjusted_runway_months, overview.runway_months)
           )
  end

  test "keeps generic provider transfer kinds when they affect runway" do
    source = insert_finance_source!(%{provider: "qonto", config_key: "qonto-main", name: "Qonto Main"})
    account = insert_finance_account!(source, %{available_balance_value: Decimal.new("900.00")})

    insert_finance_transaction!(account, %{
      external_id: "qonto-operating-transfer",
      provider: "qonto",
      direction: "debit",
      kind: "transfer",
      counterparty_name: "Contractor",
      amount_value: Decimal.new("90.00"),
      booked_at: ~U[2026-05-20 09:00:00Z],
      settled_at: ~U[2026-05-20 09:00:00Z],
      provider_updated_at: ~U[2026-05-20 09:00:00Z],
      affects_runway: true
    })

    overview = Overview.build(now: ~U[2026-05-26 12:00:00Z])

    assert overview.transaction_count_30d == 1
    assert Decimal.equal?(overview.net_30d_value, Decimal.new("-90.00"))
    assert Decimal.equal?(overview.monthly_burn_value, Decimal.new("15.00"))
    assert Decimal.equal?(overview.runway_months, Decimal.new("60.00"))
  end
end
