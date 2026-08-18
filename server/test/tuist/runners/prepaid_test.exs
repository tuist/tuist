defmodule Tuist.Runners.PrepaidTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Accounts.Account
  alias Tuist.Billing.CreditGrants
  alias Tuist.Environment
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

  defp invoice(overrides \\ %{}) do
    struct(
      %Stripe.Invoice{
        id: "in_#{System.unique_integer([:positive])}",
        customer: "cus_#{System.unique_integer([:positive])}",
        amount_paid: 800_000,
        currency: "usd",
        metadata: %{"tuist_prepaid_runners" => "true"}
      },
      overrides
    )
  end

  describe "prepaid_invoice?/1" do
    test "is false for an invoice with no marker" do
      refute Prepaid.prepaid_invoice?(invoice(%{metadata: %{}}))
      refute Prepaid.prepaid_invoice?(invoice(%{metadata: %{"tuist_prepaid_runners" => "false"}}))
      refute Prepaid.prepaid_invoice?(invoice(%{metadata: nil}))
    end

    test "is true for a marked invoice, including one whose scope is malformed" do
      assert Prepaid.prepaid_invoice?(invoice())
      assert Prepaid.prepaid_invoice?(invoice(%{metadata: %{"tuist_prepaid_runners" => "macos"}}))
      # A typo must reach the grant path and fail there rather than being
      # read as "this invoice was never prepaid".
      assert Prepaid.prepaid_invoice?(invoice(%{metadata: %{"tuist_prepaid_runners" => "mac0s"}}))
    end
  end

  describe "grant_for_paid_invoice/1" do
    test "does nothing for an invoice that is not marked prepaid" do
      reject(&CreditGrants.create/1)

      assert {:ok, :not_prepaid} = Prepaid.grant_for_paid_invoice(invoice(%{metadata: %{}}))
    end

    test "funds the grant at 1.25x what was paid, across every configured runner price" do
      invoice = invoice(%{amount_paid: 800_000})

      expect(CreditGrants, :create, fn attrs ->
        # $8,000 paid buys $10,000 of usage reported at the on-demand rate.
        assert attrs.amount_cents == 1_000_000
        assert attrs.currency == "usd"
        assert Enum.sort(attrs.price_ids) == Enum.sort([@macos_price, @linux_price])
        assert attrs.category == "paid"
        assert attrs.idempotency_key == "runner-prepaid-#{invoice.id}"
        assert attrs.metadata["tuist_runner_credit"] == "prepaid"
        assert attrs.metadata["tuist_prepaid_invoice_id"] == invoice.id
        assert attrs.metadata["tuist_prepaid_paid_cents"] == "800000"
        assert attrs.metadata["tuist_prepaid_funding_ratio_bp"] == "12500"

        {:ok, %{id: "credgr_1"}}
      end)

      assert {:ok, %{id: "credgr_1"}} = Prepaid.grant_for_paid_invoice(invoice)
    end

    test "narrows the scope to one platform when the invoice asks for it" do
      expect(CreditGrants, :create, fn attrs ->
        assert attrs.price_ids == [@macos_price]
        {:ok, %{id: "credgr_1"}}
      end)

      assert {:ok, _grant} =
               Prepaid.grant_for_paid_invoice(invoice(%{metadata: %{"tuist_prepaid_runners" => "macos"}}))
    end

    test "accepts a comma-separated platform list" do
      expect(CreditGrants, :create, fn attrs ->
        assert Enum.sort(attrs.price_ids) == Enum.sort([@macos_price, @linux_price])
        {:ok, %{id: "credgr_1"}}
      end)

      assert {:ok, _grant} =
               Prepaid.grant_for_paid_invoice(invoice(%{metadata: %{"tuist_prepaid_runners" => "macos, linux"}}))
    end

    test "honours a per-deal funding ratio" do
      expect(CreditGrants, :create, fn attrs ->
        # 30% off: $7,000 paid buys ~$10,000 of usage.
        assert attrs.amount_cents == 1_000_020
        assert attrs.metadata["tuist_prepaid_funding_ratio_bp"] == "14286"
        {:ok, %{id: "credgr_1"}}
      end)

      assert {:ok, _grant} =
               Prepaid.grant_for_paid_invoice(
                 invoice(%{
                   amount_paid: 700_000,
                   metadata: %{
                     "tuist_prepaid_runners" => "true",
                     "tuist_prepaid_runners_funding_ratio_bp" => "14286"
                   }
                 })
               )
    end

    test "rejects a funding ratio outside the sane band instead of guessing" do
      reject(&CreditGrants.create/1)

      for value <- ["1250", "9999", "20001", "125x", "12.5"] do
        assert {:error, {:invalid_metadata, :funding_ratio_bp, _value}} =
                 Prepaid.grant_for_paid_invoice(
                   invoice(%{
                     metadata: %{
                       "tuist_prepaid_runners" => "true",
                       "tuist_prepaid_runners_funding_ratio_bp" => value
                     }
                   })
                 ),
               "expected #{inspect(value)} to be rejected"
      end
    end

    test "treats an empty ratio as unset, since that is how Stripe stores one" do
      expect(CreditGrants, :create, fn attrs ->
        assert attrs.amount_cents == 1_000_000
        {:ok, %{id: "credgr_1"}}
      end)

      assert {:ok, _grant} =
               Prepaid.grant_for_paid_invoice(
                 invoice(%{
                   metadata: %{
                     "tuist_prepaid_runners" => "true",
                     "tuist_prepaid_runners_funding_ratio_bp" => "  "
                   }
                 })
               )
    end

    test "honours a per-deal expiry and rejects an out-of-range one" do
      now = ~U[2026-08-18 12:00:00Z]
      stub(DateTime, :utc_now, fn -> now end)
      expected = DateTime.add(now, 90, :day)

      expect(CreditGrants, :create, fn attrs ->
        assert attrs.expires_at == expected
        {:ok, %{id: "credgr_1"}}
      end)

      assert {:ok, _grant} =
               Prepaid.grant_for_paid_invoice(
                 invoice(%{
                   metadata: %{
                     "tuist_prepaid_runners" => "true",
                     "tuist_prepaid_runners_expires_in_days" => "90"
                   }
                 })
               )

      assert {:error, {:invalid_metadata, :expires_in_days, "0"}} =
               Prepaid.grant_for_paid_invoice(
                 invoice(%{
                   metadata: %{
                     "tuist_prepaid_runners" => "true",
                     "tuist_prepaid_runners_expires_in_days" => "0"
                   }
                 })
               )
    end

    test "defaults the expiry to a year out" do
      now = ~U[2026-08-18 12:00:00Z]
      stub(DateTime, :utc_now, fn -> now end)
      expected = DateTime.add(now, 365, :day)

      expect(CreditGrants, :create, fn attrs ->
        assert attrs.expires_at == expected
        {:ok, %{id: "credgr_1"}}
      end)

      assert {:ok, _grant} = Prepaid.grant_for_paid_invoice(invoice())
    end

    test "rejects an unknown platform" do
      reject(&CreditGrants.create/1)

      assert {:error, {:unknown_platform, "windows"}} =
               Prepaid.grant_for_paid_invoice(invoice(%{metadata: %{"tuist_prepaid_runners" => "windows"}}))
    end

    test "does not grant twice for the same invoice" do
      invoice = invoice()

      stub(CreditGrants, :list_for_customer, fn _customer_id ->
        {:ok, [%{id: "credgr_1", metadata: %{"tuist_prepaid_invoice_id" => invoice.id}}]}
      end)

      reject(&CreditGrants.create/1)

      assert {:ok, :already_granted} = Prepaid.grant_for_paid_invoice(invoice)
    end

    test "recognises an existing grant whose metadata keys came back atomized" do
      invoice = invoice()

      stub(CreditGrants, :list_for_customer, fn _customer_id ->
        {:ok, [%{id: "credgr_1", metadata: %{tuist_prepaid_invoice_id: invoice.id}}]}
      end)

      reject(&CreditGrants.create/1)

      assert {:ok, :already_granted} = Prepaid.grant_for_paid_invoice(invoice)
    end

    test "keeps the grant owed when no runner price exists yet" do
      stub(Environment, :stripe_prices, fn -> %{"runners" => %{}} end)
      reject(&CreditGrants.create/1)

      assert {:error, :no_runner_prices_configured} = Prepaid.grant_for_paid_invoice(invoice())
    end

    test "refuses to fund a grant from an invoice that collected nothing" do
      reject(&CreditGrants.create/1)

      assert {:error, {:invalid_amount_paid, 0}} = Prepaid.grant_for_paid_invoice(invoice(%{amount_paid: 0}))
    end
  end

  describe "grant_trial/3" do
    test "is the same grant, marked promotional and expiring sooner" do
      now = ~U[2026-08-18 12:00:00Z]
      stub(DateTime, :utc_now, fn -> now end)
      expected = DateTime.add(now, 30, :day)

      expect(CreditGrants, :create, fn attrs ->
        assert attrs.customer_id == "cus_trial"
        assert attrs.amount_cents == 5_000
        assert attrs.category == "promotional"
        assert attrs.expires_at == expected
        # Burns ahead of anything the customer paid for.
        assert attrs.priority == 25
        assert attrs.metadata["tuist_runner_credit"] == "trial"
        assert Enum.sort(attrs.price_ids) == Enum.sort([@macos_price, @linux_price])

        {:ok, %{id: "credgr_trial"}}
      end)

      assert {:ok, _grant} = Prepaid.grant_trial(%Account{customer_id: "cus_trial"}, 5_000)
    end

    test "can be scoped to one platform and given a different clock" do
      now = ~U[2026-08-18 12:00:00Z]
      stub(DateTime, :utc_now, fn -> now end)
      expected = DateTime.add(now, 14, :day)

      expect(CreditGrants, :create, fn attrs ->
        assert attrs.price_ids == [@macos_price]
        assert attrs.expires_at == expected
        {:ok, %{id: "credgr_trial"}}
      end)

      assert {:ok, _grant} =
               Prepaid.grant_trial(%Account{customer_id: "cus_trial"}, 5_000,
                 platforms: [:macos],
                 expires_in_days: 14
               )
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
      soon = ~U[2026-09-01 00:00:00Z]
      later = ~U[2027-01-01 00:00:00Z]

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
end
