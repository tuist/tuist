defmodule Atlas.Accounts.SnapshotTest do
  use ExUnit.Case, async: true

  alias Atlas.Accounts.Snapshot

  test "normalizes renewable contracts into monthly revenue and arr in eur" do
    snapshot =
      Snapshot.build(
        [
          %{
            id: "northstar",
            segment: :customer,
            status: "active",
            current_value: Decimal.new("12000"),
            currency: "EUR",
            next_renewal_date: ~D[2027-01-01],
            metadata: %{}
          },
          %{
            id: "harbor",
            segment: :customer,
            status: "active",
            current_value: Decimal.new("1170.2"),
            currency: "USD",
            next_renewal_date: ~D[2026-10-01],
            metadata: %{
              "current_term" => %{
                "payment" => "quarterly",
                "start_date" => "2026-07-01",
                "end_date" => "2026-10-01"
              }
            }
          }
        ],
        %{},
        %{
          published_on: ~D[2026-04-30],
          rates: %{"USD" => Decimal.new("1.1702")}
        }
      )

    assert Decimal.equal?(snapshot.monthly_revenue_eur, Decimal.new("1333.33"))
    assert Decimal.equal?(snapshot.estimated_arr_eur, Decimal.new("16000.00"))
    assert snapshot.renewal_base_count == 2
    assert Decimal.equal?(snapshot.usd_to_eur_rate, Decimal.new("0.8546"))
    assert snapshot.published_on == ~D[2026-04-30]
  end

  test "falls back to enterprise term events when account metadata is missing" do
    account = %{
      id: "delivery-hero",
      segment: :customer,
      status: "active",
      current_value: Decimal.new("7980"),
      currency: "EUR",
      next_renewal_date: ~D[2027-01-01],
      metadata: %{}
    }

    term_event = %{
      occurred_at: ~U[2026-01-01 00:00:00Z],
      metadata: %{"payment" => "yearly", "end_date" => "2027-01-01"}
    }

    snapshot = Snapshot.build([account], %{"delivery-hero" => term_event}, nil)

    assert Decimal.equal?(snapshot.monthly_revenue_eur, Decimal.new("665.00"))
    assert Decimal.equal?(snapshot.estimated_arr_eur, Decimal.new("7980.00"))
    assert snapshot.renewal_base_count == 1
    assert snapshot.usd_to_eur_rate == nil
    assert Snapshot.note(snapshot) =~ "Estimated ARR annualizes"
  end

  test "prefers the active term over stale account value" do
    snapshot =
      Snapshot.build(
        [
          %{
            id: "northstar",
            segment: :customer,
            status: "active",
            current_value: Decimal.new("1200"),
            currency: "EUR",
            next_renewal_date: nil,
            metadata: %{},
            terms: [
              %{
                payment: "yearly",
                start_date: ~D[2026-01-01],
                end_date: ~D[2026-12-31],
                total: Decimal.new("24000"),
                currency: "EUR"
              },
              %{
                payment: "yearly",
                start_date: ~D[2025-01-01],
                end_date: ~D[2025-12-31],
                total: Decimal.new("12000"),
                currency: "EUR"
              }
            ]
          }
        ],
        %{},
        nil
      )

    assert Decimal.equal?(snapshot.monthly_revenue_eur, Decimal.new("2000.00"))
    assert Decimal.equal?(snapshot.estimated_arr_eur, Decimal.new("24000.00"))
    assert snapshot.renewal_base_count == 1
  end

  test "uses signed terms for accounts without account-level current value" do
    snapshot =
      Snapshot.build(
        [
          %{
            id: "harbor",
            segment: :customer,
            status: "active",
            current_value: nil,
            currency: nil,
            next_renewal_date: nil,
            metadata: %{},
            terms: [
              %{
                payment: "yearly",
                start_date: ~D[2026-01-01],
                end_date: ~D[2026-12-31],
                total: Decimal.new("12000"),
                currency: "EUR"
              }
            ]
          }
        ],
        %{},
        nil
      )

    assert Decimal.equal?(snapshot.monthly_revenue_eur, Decimal.new("1000.00"))
    assert Decimal.equal?(snapshot.estimated_arr_eur, Decimal.new("12000.00"))
    assert snapshot.renewal_base_count == 1
  end

  test "does not treat monthly-billed term totals as monthly revenue" do
    snapshot =
      Snapshot.build(
        [
          %{
            id: "wise",
            segment: :customer,
            status: "active",
            current_value: nil,
            currency: "USD",
            next_renewal_date: nil,
            metadata: %{},
            terms: [
              %{
                payment: "monthly",
                start_date: ~D[2026-09-01],
                end_date: ~D[2027-08-31],
                total: Decimal.new("9000"),
                currency: "USD"
              }
            ]
          }
        ],
        %{},
        %{
          published_on: ~D[2026-04-30],
          rates: %{"USD" => Decimal.new("1")}
        }
      )

    assert Decimal.equal?(snapshot.monthly_revenue_eur, Decimal.new("750.00"))
    assert Decimal.equal?(snapshot.estimated_arr_eur, Decimal.new("9000.00"))
    assert snapshot.renewal_base_count == 1
  end

  test "includes customer accounts without active status" do
    snapshot =
      Snapshot.build(
        [
          %{
            id: "closed-won-customer",
            segment: :customer,
            status: nil,
            current_value: Decimal.new("12000"),
            currency: "EUR",
            next_renewal_date: ~D[2027-01-01],
            metadata: %{}
          },
          %{
            id: "not-account",
            segment: :customer,
            status: nil,
            current_value: Decimal.new("12000"),
            currency: "EUR",
            next_renewal_date: ~D[2027-01-01],
            metadata: %{},
            not_an_account_at: ~U[2026-05-01 00:00:00Z]
          },
          %{
            id: "churned",
            segment: :customer,
            status: "churned",
            current_value: Decimal.new("12000"),
            currency: "EUR",
            next_renewal_date: ~D[2027-01-01],
            metadata: %{}
          }
        ],
        %{},
        nil
      )

    assert Decimal.equal?(snapshot.monthly_revenue_eur, Decimal.new("1000.00"))
    assert Decimal.equal?(snapshot.estimated_arr_eur, Decimal.new("12000.00"))
    assert snapshot.renewal_base_count == 1
  end

  test "skips accounts without usable value, currency, or term" do
    accounts = [
      %{
        id: "missing-value",
        segment: :customer,
        status: "active",
        current_value: nil,
        currency: "EUR",
        next_renewal_date: ~D[2027-01-01],
        metadata: %{}
      },
      %{
        id: "zero-account-value",
        segment: :customer,
        status: "active",
        current_value: Decimal.new("0"),
        currency: "EUR",
        next_renewal_date: ~D[2027-01-01],
        metadata: %{}
      },
      %{
        id: "missing-rate",
        segment: :customer,
        status: "active",
        current_value: Decimal.new("1200"),
        currency: "GBP",
        next_renewal_date: ~D[2027-01-01],
        metadata: %{}
      },
      %{
        id: "missing-term",
        segment: :customer,
        status: "active",
        current_value: Decimal.new("1200"),
        currency: "EUR",
        next_renewal_date: nil,
        metadata: %{}
      },
      %{
        id: "lead",
        segment: :lead,
        status: "active",
        current_value: Decimal.new("1200"),
        currency: "EUR",
        next_renewal_date: ~D[2027-01-01],
        metadata: %{}
      },
      %{
        id: "churned",
        segment: :customer,
        status: "churned",
        current_value: Decimal.new("1200"),
        currency: "EUR",
        next_renewal_date: ~D[2027-01-01],
        metadata: %{}
      }
    ]

    snapshot = Snapshot.build(accounts, %{}, %{published_on: ~D[2026-04-30], rates: %{}})

    assert Decimal.equal?(snapshot.monthly_revenue_eur, Decimal.new("0.00"))
    assert Decimal.equal?(snapshot.estimated_arr_eur, Decimal.new("0.00"))
    assert snapshot.renewal_base_count == 0
  end

  test "falls back to the renewal assumption for whole-term contracts without an end date" do
    snapshot =
      Snapshot.build(
        [
          %{
            id: "acme",
            segment: :customer,
            status: "active",
            current_value: nil,
            currency: "EUR",
            next_renewal_date: ~D[2027-01-01],
            metadata: %{},
            terms: [
              %{
                payment: "whole-term",
                start_date: ~D[2026-01-01],
                end_date: nil,
                total: Decimal.new("12000"),
                currency: "EUR"
              }
            ]
          }
        ],
        %{},
        nil
      )

    assert Decimal.equal?(snapshot.monthly_revenue_eur, Decimal.new("1000.00"))
    assert Decimal.equal?(snapshot.estimated_arr_eur, Decimal.new("12000.00"))
    assert snapshot.renewal_base_count == 1
  end

  test "does not inflate revenue for a degenerate term whose start and end dates match" do
    snapshot =
      Snapshot.build(
        [
          %{
            id: "acme",
            segment: :customer,
            status: "active",
            current_value: nil,
            currency: "EUR",
            next_renewal_date: nil,
            metadata: %{},
            terms: [
              %{
                payment: "yearly",
                start_date: ~D[2026-01-01],
                end_date: ~D[2026-01-01],
                total: Decimal.new("12000"),
                currency: "EUR"
              }
            ]
          }
        ],
        %{},
        nil
      )

    assert Decimal.equal?(snapshot.monthly_revenue_eur, Decimal.new("1000.00"))
    assert Decimal.equal?(snapshot.estimated_arr_eur, Decimal.new("12000.00"))
    assert snapshot.renewal_base_count == 1
  end

  test "derives term length from valid date metadata" do
    snapshot =
      Snapshot.build(
        [
          %{
            id: "northstar",
            segment: :customer,
            status: "active",
            current_value: Decimal.new("3043.75"),
            currency: "EUR",
            next_renewal_date: nil,
            metadata: %{
              "current_term" => %{
                "start_date" => "2026-01-01",
                "end_date" => "2026-04-01"
              }
            }
          }
        ],
        %{},
        nil
      )

    assert Decimal.equal?(snapshot.monthly_revenue_eur, Decimal.new("1029.38"))
    assert Decimal.equal?(snapshot.estimated_arr_eur, Decimal.new("12352.55"))
    assert snapshot.renewal_base_count == 1
  end
end
