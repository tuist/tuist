defmodule Atlas.Finance.RunwayTest do
  use Atlas.DataCase, async: true

  import Atlas.FinanceFixtures

  alias Atlas.Finance.Runway

  @now ~U[2026-05-27 12:00:00Z]

  describe "per-metric analytics" do
    setup do
      source =
        insert_finance_source!(%{
          provider: "qonto",
          config_key: "qonto-main",
          name: "Qonto Main"
        })

      account =
        insert_finance_account!(source, %{
          available_balance_value: Decimal.new("9000.00"),
          balance_value: Decimal.new("9000.00")
        })

      # An old anchor transaction (outside every bucket's window) so the trailing
      # burn window has a full history before "now" — otherwise burn is `nil` for
      # want of coverage. It sits before the bucket range, so it shapes neither
      # the reconstructed balance nor the per-bucket net flow.
      insert_finance_transaction!(account, %{
        external_id: "txn-anchor",
        direction: "debit",
        amount_value: Decimal.new("100.00"),
        booked_at: ~U[2025-11-05 09:00:00Z],
        settled_at: ~U[2025-11-05 09:00:00Z],
        provider_updated_at: ~U[2025-11-05 09:00:00Z]
      })

      # A single 3,000 debit one day before "now".
      insert_finance_transaction!(account, %{
        external_id: "txn-payroll",
        direction: "debit",
        amount_value: Decimal.new("3000.00"),
        booked_at: ~U[2026-05-26 09:00:00Z],
        settled_at: ~U[2026-05-26 09:00:00Z],
        provider_updated_at: ~U[2026-05-26 09:00:00Z]
      })

      window = Runway.window(now: @now, history_days: 28, step_days: 7)
      %{window: window, today: DateTime.to_date(@now)}
    end

    test "window exposes shared metadata", %{window: window, today: today} do
      assert window.currency == "EUR"
      assert window.burn_window_days == 180
      assert window.account_count == 1
      assert window.step_days == 7
      assert length(window.dates) == 5
      assert List.last(window.dates) == today
      assert List.first(window.dates) == Date.add(today, -28)
    end

    test "cash_analytics reconstructs balance backwards from current cash", %{
      window: window,
      today: today
    } do
      cash = Runway.cash_analytics(window)

      assert cash.currency == "EUR"
      assert cash.dates == window.dates
      # Latest bucket equals the current available cash.
      assert Decimal.equal?(cash.value, Decimal.new("9000.00"))
      assert Decimal.equal?(List.last(cash.values), Decimal.new("9000.00"))
      # Earlier buckets predate the debit, so the balance was higher by 3,000.
      assert Decimal.equal?(List.first(cash.values), Decimal.new("12000.00"))
      # Cash dropped over the window, so the trend is negative.
      assert cash.trend < 0.0

      assert List.last(cash.dates) == today
    end

    test "burn_rate_analytics normalizes the trailing window to a month", %{window: window} do
      burn = Runway.burn_rate_analytics(window)

      # 3,000 over the 180 day window == 500 / month at today.
      assert Decimal.equal?(burn.value, Decimal.new("500"))
      assert Decimal.equal?(List.last(burn.values), Decimal.new("500"))
      # A covered bucket before the debit entered the window has zero burn.
      assert Decimal.equal?(Enum.at(burn.values, 1), Decimal.new("0"))
      # The earliest bucket lacks a full window of history, so burn is unknown.
      assert is_nil(List.first(burn.values))
    end

    test "runway_analytics divides balance by burn, nil when no burn", %{window: window} do
      runway = Runway.runway_analytics(window)

      # 9,000 / 500 == 18 months at today.
      assert Decimal.equal?(runway.value, Decimal.new("18"))
      assert Decimal.equal?(List.last(runway.values), Decimal.new("18"))
      # Undefined where there is no burn.
      assert is_nil(List.first(runway.values))
    end

    test "net_flow_analytics reports per-bucket net cash flow", %{window: window} do
      net_flow = Runway.net_flow_analytics(window)

      # The debit lands in the latest weekly bucket only.
      assert Decimal.equal?(net_flow.value, Decimal.new("-3000.00"))
      assert Decimal.equal?(List.last(net_flow.values), Decimal.new("-3000.00"))
      assert Decimal.equal?(List.first(net_flow.values), Decimal.new("0"))
    end

    test "cash_flow_analytics buckets income and expenses per calendar month", %{window: window} do
      cash_flow = Runway.cash_flow_analytics(window)

      assert cash_flow.currency == "EUR"
      # Setup: 100 debit on 2025-11-05 and 3,000 debit on 2026-05-26, no credits.
      assert Enum.all?(cash_flow.income, &Decimal.equal?(&1, Decimal.new("0")))
      assert Decimal.equal?(cash_flow.income_value, Decimal.new("0"))
      assert Decimal.equal?(cash_flow.expense_value, Decimal.new("3000.00"))
      # Latest bucket ends in May; the only May debit is 3,000.
      assert Decimal.equal?(List.last(cash_flow.expense), Decimal.new("3000.00"))
    end
  end

  test "cash balance includes transfers while burn/net exclude them" do
    source =
      insert_finance_source!(%{provider: "qonto", config_key: "qonto-main", name: "Qonto Main"})

    account =
      insert_finance_account!(source, %{
        available_balance_value: Decimal.new("9000.00"),
        balance_value: Decimal.new("9000.00")
      })

    # A cash-affecting transfer out that is NOT runway-relevant (e.g. moving money
    # to an external account). It must shape the bank balance but not the burn.
    insert_finance_transaction!(account, %{
      external_id: "txn-transfer",
      direction: "debit",
      amount_value: Decimal.new("5000.00"),
      affects_cash_balance: true,
      affects_runway: false,
      booked_at: ~U[2026-05-26 09:00:00Z],
      settled_at: ~U[2026-05-26 09:00:00Z],
      provider_updated_at: ~U[2026-05-26 09:00:00Z]
    })

    window = Runway.window(now: @now, history_days: 28, step_days: 7)

    cash = Runway.cash_analytics(window)
    # Before the transfer the balance was 5,000 higher than today's 9,000.
    assert Decimal.equal?(List.last(cash.values), Decimal.new("9000.00"))
    assert Decimal.equal?(List.first(cash.values), Decimal.new("14000.00"))

    # The transfer is excluded from runway-relevant flow, so burn stays zero.
    burn = Runway.burn_rate_analytics(window)
    Enum.each(burn.values, fn value -> assert Decimal.equal?(value, Decimal.new("0")) end)

    net_flow = Runway.net_flow_analytics(window)
    Enum.each(net_flow.values, fn value -> assert Decimal.equal?(value, Decimal.new("0")) end)
  end

  test "includes provider-completed transactions regardless of status label (e.g. Mercury \"sent\")" do
    source =
      insert_finance_source!(%{provider: "mercury", config_key: "mercury-main", name: "Mercury Main"})

    account =
      insert_finance_account!(source, %{
        available_balance_value: Decimal.new("9000.00"),
        balance_value: Decimal.new("9000.00")
      })

    # Mercury marks completed transactions as "sent", not "completed". The flags
    # still mark it cash- and runway-relevant, so it must shape every series even
    # though the status label differs from Qonto's "completed".
    insert_finance_transaction!(account, %{
      external_id: "txn-sent",
      status: "sent",
      direction: "debit",
      amount_value: Decimal.new("3000.00"),
      affects_cash_balance: true,
      affects_runway: true,
      booked_at: ~U[2026-05-26 09:00:00Z],
      settled_at: ~U[2026-05-26 09:00:00Z],
      provider_updated_at: ~U[2026-05-26 09:00:00Z]
    })

    window = Runway.window(now: @now, history_days: 28, step_days: 7)

    cash = Runway.cash_analytics(window)
    # The "sent" debit is applied: earlier buckets sit 3,000 above today's 9,000.
    assert Decimal.equal?(List.last(cash.values), Decimal.new("9000.00"))
    assert Decimal.equal?(List.first(cash.values), Decimal.new("12000.00"))

    # And it counts toward the runway-relevant net flow too.
    net_flow = Runway.net_flow_analytics(window)
    assert Decimal.equal?(List.last(net_flow.values), Decimal.new("-3000.00"))
  end

  test "analytics return flat/zero series when there is no data" do
    window = Runway.window(now: @now, history_days: 14, step_days: 7)

    assert window.account_count == 0
    assert length(window.dates) == 3
    assert Decimal.equal?(window.current_balance, Decimal.new("0"))

    cash = Runway.cash_analytics(window)
    Enum.each(cash.values, fn value -> assert Decimal.equal?(value, Decimal.new("0")) end)
    assert is_nil(cash.trend)

    burn = Runway.burn_rate_analytics(window)
    Enum.each(burn.values, fn value -> assert Decimal.equal?(value, Decimal.new("0")) end)

    runway = Runway.runway_analytics(window)
    Enum.each(runway.values, fn value -> assert is_nil(value) end)
    assert is_nil(runway.value)
  end

  test "window picks weekly buckets for short ranges and monthly for large ones" do
    weekly = Runway.window(now: @now, history_days: 60)
    monthly = Runway.window(now: @now, history_days: 365)

    assert weekly.step_days == 7
    # Buckets anchored at today: div(60, 7) == 8 steps back + today == 9 points.
    assert length(weekly.dates) == 9

    assert monthly.step_days == 30
    # div(365, 30) == 12 steps back + today == 13 points.
    assert length(monthly.dates) == 13
  end
end
