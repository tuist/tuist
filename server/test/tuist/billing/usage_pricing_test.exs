defmodule Tuist.Billing.UsagePricingTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Billing
  alias Tuist.Billing.UsageMeters
  alias Tuist.Billing.UsagePricing
  alias TuistTestSupport.Fixtures.AccountsFixtures

  @period_start ~U[2026-05-01 00:00:00.000000Z]
  @period_end ~U[2026-06-01 00:00:00.000000Z]

  setup do
    account = AccountsFixtures.organization_fixture(preload: [:account]).account
    stub(DateTime, :utc_now, fn -> ~U[2026-06-10 00:00:00.000000Z] end)
    stub(Billing, :get_current_active_subscription, fn _account -> nil end)
    stub(UsageMeters, :cache_downloads, fn _account_id, _start, _end -> [] end)
    stub(UsageMeters, :test_case_runs, fn _account_id, _start, _end -> [] end)

    %{account: account}
  end

  defp cache_row(attrs),
    do: Map.merge(%{date: ~D[2026-05-10], cache: :module, runners: false, bytes: 0, requests: 0}, attrs)

  defp test_row(attrs), do: Map.merge(%{date: ~D[2026-05-10], status: "success", runners: false, count: 0}, attrs)

  describe "meter_values/3" do
    test "halves runner traffic and reports egress in whole megabytes", %{account: account} do
      account_id = account.id

      expect(UsageMeters, :cache_downloads, fn ^account_id, @period_start, @period_end ->
        [
          cache_row(%{cache: :module, bytes: 3_999_999, requests: 10}),
          cache_row(%{cache: :xcode, runners: true, bytes: 2_000_001, requests: 7})
        ]
      end)

      expect(UsageMeters, :test_case_runs, fn ^account_id, @period_start, @period_end ->
        [
          test_row(%{status: "success", count: 40}),
          test_row(%{status: "failure", count: 5}),
          test_row(%{status: "skipped", count: 3}),
          test_row(%{status: "success", runners: true, count: 100})
        ]
      end)

      assert UsagePricing.meter_values(account, @period_start, @period_end) == [
               # 3,999,999 + 2,000,001 / 2 = 4,999,999 bytes
               %{event_name: "cache_egress_megabytes", value: 4},
               # 10 + 7 / 2
               %{event_name: "cache_requests", value: 13},
               %{event_name: "passing_test_cases", value: 40}
             ]
    end
  end

  describe "period_breakdown/2" do
    test "charges nothing for usage that exactly fills each allowance", %{account: account} do
      stub(UsageMeters, :cache_downloads, fn _, _, _ ->
        [cache_row(%{bytes: 100_000_000_000, requests: 1_000_000})]
      end)

      stub(UsageMeters, :test_case_runs, fn _, _, _ -> [test_row(%{count: 5_000_000})] end)

      breakdown = UsagePricing.period_breakdown(account, {@period_start, @period_end})

      assert breakdown.cache.egress.gross == Money.new(3_500, :USD)
      assert breakdown.cache.egress.included_credit == Money.new(3_500, :USD)
      assert breakdown.cache.egress.charge == Money.new(0, :USD)
      assert breakdown.cache.requests.gross == Money.new(1_000, :USD)
      assert breakdown.cache.requests.charge == Money.new(0, :USD)
      assert breakdown.tests.gross == Money.new(1_000, :USD)
      assert breakdown.tests.charge == Money.new(0, :USD)
    end

    test "charges the usage past each allowance at its rate", %{account: account} do
      stub(UsageMeters, :cache_downloads, fn _, _, _ ->
        [cache_row(%{bytes: 110_000_000_000, requests: 1_250_000})]
      end)

      stub(UsageMeters, :test_case_runs, fn _, _, _ -> [test_row(%{count: 8_000_000})] end)

      breakdown = UsagePricing.period_breakdown(account, {@period_start, @period_end})

      # 10 GB at $0.35
      assert breakdown.cache.egress.billable == 10_000_000_000
      assert breakdown.cache.egress.charge == Money.new(350, :USD)
      # 250,000 requests at $0.01 per 1,000
      assert breakdown.cache.requests.charge == Money.new(250, :USD)
      assert breakdown.cache.charge == Money.new(600, :USD)
      # 3 million passing test cases at $2 per million
      assert breakdown.tests.billable == 3_000_000
      assert breakdown.tests.charge == Money.new(600, :USD)
    end

    test "counts runner traffic at half before the shared allowance", %{account: account} do
      stub(UsageMeters, :cache_downloads, fn _, _, _ ->
        [
          cache_row(%{cache: :module, bytes: 80_000_000_000, requests: 900_000}),
          cache_row(%{cache: :xcode, runners: true, bytes: 60_000_000_000, requests: 400_000})
        ]
      end)

      breakdown = UsagePricing.period_breakdown(account, {@period_start, @period_end})
      egress = breakdown.cache.egress

      assert egress.quantity == 140_000_000_000
      assert egress.metered == 110_000_000_000
      assert egress.gross == Money.new(4_900, :USD)
      assert egress.runner_credit == Money.new(1_050, :USD)
      assert egress.included_credit == Money.new(3_500, :USD)
      assert egress.charge == Money.new(350, :USD)
      assert breakdown.cache.requests.metered == 1_100_000
      assert breakdown.cache.requests.charge == Money.new(100, :USD)
    end

    test "bills only passing test cases that did not run on Tuist Runners", %{account: account} do
      stub(UsageMeters, :test_case_runs, fn _, _, _ ->
        [
          test_row(%{status: "success", count: 6_000_000}),
          test_row(%{status: "failure", count: 2_000_000}),
          test_row(%{status: "skipped", count: 1_000_000}),
          test_row(%{status: "success", runners: true, count: 4_000_000}),
          test_row(%{status: "failure", runners: true, count: 500})
        ]
      end)

      tests = UsagePricing.period_breakdown(account, {@period_start, @period_end}).tests

      assert tests.passed == 6_000_000
      assert tests.failed == 2_000_000
      assert tests.skipped == 1_000_000
      assert tests.on_runners == 4_000_500
      assert tests.charge == Money.new(200, :USD)
    end

    test "only bills an account with a subscription", %{account: account} do
      stub(UsageMeters, :test_case_runs, fn _, _, _ -> [test_row(%{count: 6_000_000})] end)

      assert %{cache: %{billed: nil}, tests: %{billed: nil, charge: charge}} =
               UsagePricing.period_breakdown(account, {@period_start, @period_end})

      assert charge == Money.new(200, :USD)

      stub(Billing, :get_current_active_subscription, fn _account -> %{plan: :pro} end)

      assert %{cache: %{billed: cache_billed}, tests: %{billed: tests_billed}} =
               UsagePricing.period_breakdown(account, {@period_start, @period_end})

      assert cache_billed == Money.new(0, :USD)
      assert tests_billed == Money.new(200, :USD)
    end

    test "projects an open period from the days that have passed", %{account: account} do
      stub(DateTime, :utc_now, fn -> ~U[2026-05-11 00:00:00.000000Z] end)

      account_id = account.id
      usage_end = ~U[2026-05-11 00:00:00.000000Z]

      expect(UsageMeters, :cache_downloads, fn ^account_id, @period_start, ^usage_end ->
        [cache_row(%{date: ~D[2026-05-10], bytes: 10_000_000_000, requests: 1_000})]
      end)

      breakdown = UsagePricing.period_breakdown(account, {@period_start, @period_end})

      assert breakdown.cache.days == [%{date: ~D[2026-05-10], cache: :module, bytes: 10_000_000_000, requests: 1_000}]

      assert breakdown.cache.charge_days == [
               %{date: ~D[2026-05-10], meter: :egress, dollars: 3.5},
               %{date: ~D[2026-05-10], meter: :requests, dollars: 0.01}
             ]

      assert %{bytes: bytes, requests: requests, dollars: dollars} = hd(breakdown.cache.projected_days)
      assert {round(bytes), round(requests), Float.round(dollars, 4)} == {909_090_909, 91, 0.3191}
      assert breakdown.usage_through == ~D[2026-05-11]
      assert breakdown.cache.egress.projected == 31_000_000_000
      assert [%{date: ~D[2026-05-12]} | _] = breakdown.cache.projected_days
      assert List.last(breakdown.cache.projected_days).date == ~D[2026-05-31]
    end
  end
end
