defmodule Tuist.Runners.PrepaidTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Accounts.Account
  alias Tuist.Billing
  alias Tuist.Billing.CreditGrants
  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.Runners.Prepaid

  @macos_price "price_runner_macos"
  @linux_price "price_runner_linux"

  setup do
    stub(Environment, :stripe_prices, fn ->
      %{
        "runners" => %{
          "runner_macos_compute_unit_milliseconds" => @macos_price,
          "runner_linux_compute_unit_milliseconds" => @linux_price
        }
      }
    end)

    stub(CreditGrants, :list_for_customer, fn _customer_id -> {:ok, []} end)

    :ok
  end

  describe "on_demand_cost_for_milliseconds/2" do
    test "charges a macOS baseline minute $0.06" do
      assert Prepaid.on_demand_cost_for_milliseconds(:macos, 100 * 60_000) == Money.new(600, :USD)
    end

    test "charges a Linux baseline minute $0.0024, as the pricing page lists for 2 vCPU / 8 GB" do
      assert Prepaid.on_demand_cost_for_milliseconds(:linux, 1_000 * 60_000) == Money.new(240, :USD)
    end

    test "charges the 1 vCPU / 2 GB Linux machine $0.001 a minute through its multiplier" do
      multiplier = Tuist.Runners.Catalog.billing_multiplier(:linux, 1, 2)
      units = div(10_000 * 60_000 * multiplier, 10_000)

      # The multiplier truncates to a basis point, so 10,000 minutes come
      # to a hair under $10.
      assert Prepaid.on_demand_cost_for_milliseconds(:linux, units) == Money.new(999, :USD)
      assert_in_delta Prepaid.on_demand_dollars(:linux, units), 10.0, 0.01
    end
  end

  describe "refresh_balance/1" do
    test "writes the cache even when nothing is left" do
      # summarize/1 answers nil for an account holding nothing, and the
      # refresh used to skip writing nil. The stale entry survived, the
      # page went on serving the figure from before the clear, and
      # setting zero looked impossible.
      stub(CreditGrants, :list_for_customer, fn _customer_id -> {:ok, []} end)

      expect(KeyValueStore, :put, fn _key, value, opts ->
        assert opts[:cache] == :display
        assert is_nil(value)
        value
      end)

      assert is_nil(Prepaid.refresh_balance("cus_empty"))
    end
  end

  describe "balance/2" do
    defp grant(overrides) do
      Map.merge(
        %{
          id: "credgr_#{System.unique_integer([:positive])}",
          metadata: %{"tuist_runner_credit" => "prepaid"},
          amount: %{type: "monetary", monetary: %{currency: "usd", value: 1_000_000}},
          expires_at: nil
        },
        overrides
      )
    end

    defp account, do: %Account{customer_id: "cus_#{System.unique_integer([:positive])}"}

    test "sums what is left and reports the soonest expiry" do
      soon = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(1, :day)
      later = DateTime.shift(soon, year: 1)

      soon_grant = grant(%{expires_at: DateTime.to_unix(soon)})
      later_grant = grant(%{expires_at: DateTime.to_unix(later)})

      stub(CreditGrants, :list_for_customer, fn _customer_id -> {:ok, [later_grant, soon_grant]} end)

      stub(CreditGrants, :available_balance_cents, fn _customer_id, grant_id ->
        case grant_id do
          id when id == soon_grant.id -> {:ok, 250_000}
          _ -> {:ok, 400_000}
        end
      end)

      balance = Prepaid.balance(account())

      assert balance.available == Money.new(650_000, :USD)
      assert balance.expires_at == soon
      assert Enum.map(balance.grants, & &1.id) == [soon_grant.id, later_grant.id]
    end

    test "ignores grants Stripe has already expired" do
      expired = grant(%{expires_at: DateTime.to_unix(~U[2020-01-01 00:00:00Z])})
      live = grant(%{expires_at: DateTime.to_unix(~U[2099-01-01 00:00:00Z])})

      stub(CreditGrants, :list_for_customer, fn _customer_id -> {:ok, [expired, live]} end)

      expect(CreditGrants, :available_balance_cents, fn _customer_id, grant_id ->
        assert grant_id == live.id
        {:ok, 100}
      end)

      balance = Prepaid.balance(account())

      assert balance.available == Money.new(100, :USD)
      assert Enum.map(balance.grants, & &1.id) == [live.id]
    end

    test "ignores grants that are not runner credit" do
      stub(CreditGrants, :list_for_customer, fn _customer_id ->
        {:ok, [grant(%{metadata: %{"some_other_product" => "true"}}), grant(%{metadata: nil})]}
      end)

      reject(&CreditGrants.available_balance_cents/2)

      assert Prepaid.balance(account()) == nil
    end

    test "shows nothing once the credit is spent" do
      stub(CreditGrants, :list_for_customer, fn _customer_id -> {:ok, [grant(%{})]} end)
      stub(CreditGrants, :available_balance_cents, fn _customer_id, _grant_id -> {:ok, 0} end)

      assert Prepaid.balance(account()) == nil
    end

    test "reports nothing rather than raising when Stripe cannot be reached" do
      stub(CreditGrants, :list_for_customer, fn _customer_id -> {:error, :timeout} end)

      assert Prepaid.balance(account()) == nil
    end

    test "reports nothing for an account with no Stripe customer" do
      reject(&CreditGrants.list_for_customer/1)

      assert Prepaid.balance(%Account{customer_id: nil}) == nil
    end
  end

  describe "balance/2 purchased total" do
    test "reports what was bought as well as what is left" do
      # Unique per run: the balance is cached by customer id, so a fixed
      # one would be answered from a previous test's entry.
      customer_id = "cus_granted_#{System.unique_integer([:positive])}"
      account = %Account{customer_id: customer_id}

      stub(CreditGrants, :list_for_customer, fn ^customer_id ->
        {:ok,
         [
           %{
             id: "credgr_1",
             metadata: %{"tuist_runner_credit" => "prepaid"},
             amount: %{monetary: %{currency: "usd", value: 75_000}},
             expires_at: nil
           }
         ]}
      end)

      # Half spent: the balance moves, the purchase does not.
      stub(CreditGrants, :available_balance_cents, fn ^customer_id, "credgr_1" -> {:ok, 37_500} end)

      balance = Prepaid.balance(account)

      assert balance.available == Money.new(37_500, :USD)
      assert balance.granted == Money.new(75_000, :USD)
      # $750 of credit buys 12,500 minutes at the $0.06 standard rate.
      assert balance.granted_minutes == 12_500
    end

    test "counts a pool by what it has left toward the period, and a monthly grant in full" do
      # A pool's earlier periods have already drawn on it, so what it was
      # bought with overstates what this period can run on. A monthly grant
      # is only drawn down when its period's invoice closes, so mid-period
      # its purchase is the figure that does not move as usage accrues.
      customer_id = "cus_period_#{System.unique_integer([:positive])}"

      stub(CreditGrants, :list_for_customer, fn ^customer_id ->
        {:ok,
         [
           %{
             id: "credgr_monthly",
             metadata: %{"tuist_runner_credit" => "prepaid"},
             amount: %{monetary: %{currency: "usd", value: 75_000}},
             expires_at: nil
           },
           %{
             id: "credgr_pool",
             metadata: %{"tuist_runner_credit" => "pool"},
             amount: %{monetary: %{currency: "usd", value: 1_500_000}},
             expires_at: nil
           }
         ]}
      end)

      stub(CreditGrants, :available_balance_cents, fn ^customer_id, grant_id ->
        case grant_id do
          "credgr_monthly" -> {:ok, 75_000}
          "credgr_pool" -> {:ok, 300_000}
        end
      end)

      balance = Prepaid.balance(%Account{customer_id: customer_id})

      assert balance.granted_minutes == 262_500
      assert balance.period_minutes == 62_500
      assert Enum.find(balance.grants, &(&1.id == "credgr_pool")).kind == "pool"
    end
  end

  describe "grant_pool/2" do
    setup do
      stub(DateTime, :utc_now, fn -> ~U[2026-10-06 12:00:00Z] end)
      # Monthly, renewing on the 1st. Stale on purpose: the cycle is what
      # matters, not which period is current.
      stub(Billing, :current_billing_period, fn _account -> {~U[2026-08-01 00:00:00Z], ~U[2026-09-01 00:00:00Z]} end)
      :ok
    end

    defp pool_account, do: %Account{id: 9, customer_id: "cus_pool_#{System.unique_integer([:positive])}"}

    defp pool_attrs(overrides \\ %{}) do
      Map.merge(
        %{
          paid_cents: 800_000,
          credit_multiplier: Decimal.new("1.4"),
          platforms: [:macos],
          starts_on: ~D[2026-10-01],
          expires_on: ~D[2027-09-30],
          invoice_id: "in_pool"
        },
        overrides
      )
    end

    test "grants the paid amount times the credit multiplier for the contract's invoices" do
      account = pool_account()

      expect(CreditGrants, :create, fn attrs ->
        assert attrs.customer_id == account.customer_id
        assert attrs.amount_cents == 1_120_000
        assert attrs.currency == "usd"
        assert attrs.price_ids == [@macos_price]
        assert attrs.category == "paid"
        # The contract is already running, so the pool takes effect when it
        # is granted: Stripe refuses an effective date in the past.
        assert is_nil(attrs[:effective_at])
        # The invoice closing on October 1, 2027 carries the contract's last
        # day, so the pool outlives it by the grace period.
        assert attrs.expires_at == ~U[2027-10-05 00:00:00Z]
        assert attrs.metadata["tuist_runner_credit"] == "pool"
        assert attrs.metadata["tuist_prepaid_invoice_id"] == "in_pool"
        assert attrs.metadata["tuist_prepaid_paid_cents"] == "800000"
        assert attrs.metadata["tuist_prepaid_funding_ratio_bp"] == "14000"
        {:ok, %{id: "credgr_pool"}}
      end)

      assert {:ok, %{id: "credgr_pool"}} = Prepaid.grant_pool(account, pool_attrs())
    end

    test "takes effect only after the contract starts when granted ahead of it" do
      # Stripe pays an invoice from a grant when the invoice's period ends at
      # or after the grant takes effect. The October invoice closes on
      # November 1 and carries no contract usage, so it must not draw on it.
      expect(CreditGrants, :create, fn attrs ->
        assert attrs.effective_at == ~U[2026-11-01 00:00:01Z]
        assert attrs.expires_at == ~U[2027-11-05 00:00:00Z]
        {:ok, %{id: "credgr_pool"}}
      end)

      assert {:ok, _grant} =
               Prepaid.grant_pool(pool_account(), pool_attrs(%{starts_on: ~D[2026-11-01], expires_on: ~D[2027-10-31]}))
    end

    test "runs a term shorter than a year, aligned to an earlier contract" do
      expect(CreditGrants, :create, fn attrs ->
        assert attrs.effective_at == ~U[2026-11-01 00:00:01Z]
        assert attrs.expires_at == ~U[2027-09-05 00:00:00Z]
        {:ok, %{id: "credgr_pool"}}
      end)

      assert {:ok, _grant} =
               Prepaid.grant_pool(pool_account(), pool_attrs(%{starts_on: ~D[2026-11-01], expires_on: ~D[2027-08-31]}))
    end

    test "outlives the invoice carrying the contract's last day on a cycle that renews mid-month" do
      # Renewing on the 15th, the usage of September 15 to 30 is invoiced on
      # October 15, well after the contract's last day.
      stub(Billing, :current_billing_period, fn _account -> {~U[2026-09-15 00:00:00Z], ~U[2026-10-15 00:00:00Z]} end)

      expect(CreditGrants, :create, fn attrs ->
        assert attrs.expires_at == ~U[2027-10-19 00:00:00Z]
        {:ok, %{id: "credgr_pool"}}
      end)

      assert {:ok, _grant} = Prepaid.grant_pool(pool_account(), pool_attrs())
    end

    test "dates the pool from the contract alone when the account has no billing cycle" do
      stub(Billing, :current_billing_period, fn _account -> nil end)

      expect(CreditGrants, :create, fn attrs ->
        assert attrs.expires_at == ~U[2027-10-05 00:00:00Z]
        {:ok, %{id: "credgr_pool"}}
      end)

      assert {:ok, _grant} = Prepaid.grant_pool(pool_account(), pool_attrs())
    end

    test "records no invoice when none is given" do
      expect(CreditGrants, :create, fn attrs ->
        refute Map.has_key?(attrs.metadata, "tuist_prepaid_invoice_id")
        {:ok, %{id: "credgr_pool"}}
      end)

      assert {:ok, _grant} = Prepaid.grant_pool(pool_account(), pool_attrs(%{invoice_id: nil}))
    end

    test "rejects terms that are more likely a typo than a deal" do
      reject(&CreditGrants.create/1)

      cases = [
        {%{credit_multiplier: Decimal.new("0.9999")}, :credit_multiplier},
        {%{credit_multiplier: Decimal.new("2.0001")}, :credit_multiplier},
        {%{credit_multiplier: Decimal.new("1.23456")}, :credit_multiplier},
        {%{credit_multiplier: Decimal.new("12500")}, :credit_multiplier},
        {%{paid_cents: 0}, :paid_cents},
        {%{platforms: []}, :platforms},
        {%{platforms: [:windows]}, :platforms},
        {%{starts_on: nil}, :term},
        {%{starts_on: ~D[2027-10-01]}, :term},
        {%{starts_on: ~D[2026-09-30]}, :term},
        {%{expires_on: ~D[2026-10-06]}, :expires_on},
        {%{starts_on: ~D[2026-11-08], expires_on: ~D[2027-11-07]}, :expires_on},
        {%{invoice_id: "123"}, :invoice_id}
      ]

      for {overrides, field} <- cases do
        assert {:error, {:invalid_pool, ^field}} = Prepaid.grant_pool(pool_account(), pool_attrs(overrides)),
               "expected #{inspect(overrides)} to be rejected on #{field}"
      end
    end

    test "accepts a year-long contract that ends thirteen months out" do
      expect(CreditGrants, :create, fn attrs ->
        assert attrs.effective_at == ~U[2026-11-07 00:00:01Z]
        assert attrs.expires_at == ~U[2027-12-05 00:00:00Z]
        {:ok, %{id: "credgr_pool"}}
      end)

      assert {:ok, _grant} =
               Prepaid.grant_pool(pool_account(), pool_attrs(%{starts_on: ~D[2026-11-07], expires_on: ~D[2027-11-06]}))
    end

    test "also pays for a retired Price a subscription has not been moved off yet" do
      stub(Environment, :stripe_prices, fn ->
        %{
          "runners" => %{
            "runner_macos_compute_unit_milliseconds" => @macos_price,
            "runner_linux_compute_unit_milliseconds" => @linux_price
          },
          "retired_runners" => %{
            "runner_macos_compute_unit_milliseconds" => ["price_runner_macos_retired"],
            "runner_linux_compute_unit_milliseconds" => ["price_runner_linux_retired"]
          }
        }
      end)

      expect(CreditGrants, :create, fn attrs ->
        assert attrs.price_ids == [@macos_price, "price_runner_macos_retired"]
        {:ok, %{id: "credgr_pool"}}
      end)

      assert {:ok, _grant} = Prepaid.grant_pool(pool_account(), pool_attrs())
    end

    test "keeps the grant owed when no runner price exists yet" do
      stub(Environment, :stripe_prices, fn -> %{"runners" => %{}} end)
      reject(&CreditGrants.create/1)

      assert {:error, :no_runner_prices_configured} = Prepaid.grant_pool(pool_account(), pool_attrs())
    end
  end

  describe "pool_coverage/3" do
    setup do
      stub(DateTime, :utc_now, fn -> ~U[2026-10-06 12:00:00Z] end)
      :ok
    end

    test "names the first and last invoice the pool pays for" do
      coverage =
        Prepaid.pool_coverage(
          {~U[2026-09-15 00:00:00Z], ~U[2026-10-15 00:00:00Z]},
          ~D[2026-11-01],
          ~D[2027-10-31]
        )

      # The invoice closing November 15 is the first to carry contract usage,
      # and the one closing November 15 a year later carries its last day.
      assert coverage.first_invoice_at == ~U[2026-11-15 00:00:00Z]
      assert coverage.last_invoice_at == ~U[2027-11-15 00:00:00Z]
      assert coverage.effective_at == ~U[2026-11-01 00:00:01Z]
      assert coverage.expires_at == ~U[2027-11-19 00:00:00Z]
    end

    test "follows a yearly billing cycle to the renewal that invoices the contract's usage" do
      coverage =
        Prepaid.pool_coverage({~U[2026-03-01 00:00:00Z], ~U[2027-03-01 00:00:00Z]}, ~D[2026-10-01], ~D[2027-09-30])

      assert coverage.first_invoice_at == ~U[2027-03-01 00:00:00Z]
      assert coverage.last_invoice_at == ~U[2028-03-01 00:00:00Z]
      assert coverage.expires_at == ~U[2028-03-05 00:00:00Z]
    end

    test "names no invoices when there is no billing cycle to read" do
      coverage = Prepaid.pool_coverage(nil, ~D[2026-10-01], ~D[2027-09-30])

      assert is_nil(coverage.first_invoice_at)
      assert is_nil(coverage.last_invoice_at)
      assert coverage.expires_at == ~U[2027-10-05 00:00:00Z]
    end
  end
end
