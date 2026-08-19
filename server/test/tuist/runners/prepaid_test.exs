defmodule Tuist.Runners.PrepaidTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Accounts.Account
  alias Tuist.Billing.CreditGrants
  alias Tuist.Billing.Invoices
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
        currency: "usd"
      },
      overrides
    )
  end

  defp line(overrides \\ %{}) do
    Map.merge(
      %{
        id: "il_#{System.unique_integer([:positive])}",
        amount: 800_000,
        metadata: %{"tuist_prepaid_runners" => "true"}
      },
      overrides
    )
  end

  # Stubs the lines endpoint for whatever invoice is asked about, so a
  # test only has to say what is on the bill.
  defp stub_lines(lines) do
    stub(Invoices, :list_lines, fn _invoice_id -> {:ok, lines} end)
  end

  describe "grant_for_paid_invoice/1" do
    test "does nothing for an invoice with no prepaid line" do
      stub_lines([line(%{metadata: %{}}), line(%{metadata: nil})])
      reject(&CreditGrants.create/1)

      assert {:ok, :not_prepaid} = Prepaid.grant_for_paid_invoice(invoice())
    end

    test "funds the grant from the marked line, not the whole bill" do
      invoice = invoice(%{amount_paid: 950_000})
      prepaid = line(%{amount: 800_000})
      # The month's metered usage, sharing the invoice. Funding from
      # amount_paid would turn this into runner credit too.
      usage = line(%{amount: 150_000, metadata: %{}})

      stub_lines([usage, prepaid])

      expect(CreditGrants, :create, fn attrs ->
        assert attrs.amount_cents == 1_000_000
        assert attrs.currency == "usd"
        assert Enum.sort(attrs.price_ids) == Enum.sort([@macos_price, @linux_price])
        assert attrs.category == "paid"
        assert attrs.idempotency_key == "runner-prepaid-#{invoice.id}-#{prepaid.id}"
        assert attrs.metadata["tuist_runner_credit"] == "prepaid"
        assert attrs.metadata["tuist_prepaid_invoice_id"] == invoice.id
        assert attrs.metadata["tuist_prepaid_invoice_line_id"] == prepaid.id
        assert attrs.metadata["tuist_prepaid_paid_cents"] == "800000"
        assert attrs.metadata["tuist_prepaid_funding_ratio_bp"] == "12500"

        {:ok, %{id: "credgr_1"}}
      end)

      assert {:ok, [%{id: "credgr_1"}]} = Prepaid.grant_for_paid_invoice(invoice)
    end

    test "gives each prepaid line its own grant on its own terms" do
      standard = line(%{amount: 800_000})

      deeper =
        line(%{
          amount: 700_000,
          metadata: %{
            "tuist_prepaid_runners" => "macos",
            "tuist_prepaid_runners_funding_ratio_bp" => "14286"
          }
        })

      stub_lines([standard, deeper])

      expect(CreditGrants, :create, 2, fn attrs ->
        case attrs.metadata["tuist_prepaid_invoice_line_id"] do
          id when id == standard.id ->
            assert attrs.amount_cents == 1_000_000
            assert Enum.sort(attrs.price_ids) == Enum.sort([@macos_price, @linux_price])

          _ ->
            # Averaging the two into one balance would misprice both.
            assert attrs.amount_cents == 1_000_020
            assert attrs.price_ids == [@macos_price]
        end

        {:ok, %{id: "credgr_#{attrs.metadata["tuist_prepaid_invoice_line_id"]}"}}
      end)

      assert {:ok, grants} = Prepaid.grant_for_paid_invoice(invoice())
      assert length(grants) == 2
    end

    test "narrows the scope to one platform when the line asks for it" do
      stub_lines([line(%{metadata: %{"tuist_prepaid_runners" => "macos"}})])

      expect(CreditGrants, :create, fn attrs ->
        assert attrs.price_ids == [@macos_price]
        {:ok, %{id: "credgr_1"}}
      end)

      assert {:ok, [_grant]} = Prepaid.grant_for_paid_invoice(invoice())
    end

    test "rejects a funding ratio outside the sane band instead of guessing" do
      reject(&CreditGrants.create/1)

      for value <- ["1250", "9999", "20001", "125x", "12.5"] do
        stub_lines([
          line(%{
            metadata: %{
              "tuist_prepaid_runners" => "true",
              "tuist_prepaid_runners_funding_ratio_bp" => value
            }
          })
        ])

        assert {:error, {:invalid_metadata, :funding_ratio_bp, _value}} =
                 Prepaid.grant_for_paid_invoice(invoice()),
               "expected #{inspect(value)} to be rejected"
      end
    end

    test "treats an empty ratio as unset, since that is how Stripe stores one" do
      stub_lines([
        line(%{
          metadata: %{
            "tuist_prepaid_runners" => "true",
            "tuist_prepaid_runners_funding_ratio_bp" => "  "
          }
        })
      ])

      expect(CreditGrants, :create, fn attrs ->
        assert attrs.amount_cents == 1_000_000
        {:ok, %{id: "credgr_1"}}
      end)

      assert {:ok, [_grant]} = Prepaid.grant_for_paid_invoice(invoice())
    end

    test "honours a per-deal expiry and rejects an out-of-range one" do
      now = ~U[2026-08-18 12:00:00Z]
      stub(DateTime, :utc_now, fn -> now end)
      expected = DateTime.add(now, 90, :day)

      stub_lines([
        line(%{
          metadata: %{
            "tuist_prepaid_runners" => "true",
            "tuist_prepaid_runners_expires_in_days" => "90"
          }
        })
      ])

      expect(CreditGrants, :create, fn attrs ->
        assert attrs.expires_at == expected
        {:ok, %{id: "credgr_1"}}
      end)

      assert {:ok, [_grant]} = Prepaid.grant_for_paid_invoice(invoice())

      stub_lines([
        line(%{
          metadata: %{
            "tuist_prepaid_runners" => "true",
            "tuist_prepaid_runners_expires_in_days" => "0"
          }
        })
      ])

      assert {:error, {:invalid_metadata, :expires_in_days, "0"}} =
               Prepaid.grant_for_paid_invoice(invoice())
    end

    test "defaults the expiry to a year out" do
      now = ~U[2026-08-18 12:00:00Z]
      stub(DateTime, :utc_now, fn -> now end)
      expected = DateTime.add(now, 365, :day)

      stub_lines([line()])

      expect(CreditGrants, :create, fn attrs ->
        assert attrs.expires_at == expected
        {:ok, %{id: "credgr_1"}}
      end)

      assert {:ok, [_grant]} = Prepaid.grant_for_paid_invoice(invoice())
    end

    test "rejects an unknown platform" do
      stub_lines([line(%{metadata: %{"tuist_prepaid_runners" => "windows"}})])
      reject(&CreditGrants.create/1)

      assert {:error, {:unknown_platform, "windows"}} = Prepaid.grant_for_paid_invoice(invoice())
    end

    test "does not grant twice for the same line" do
      prepaid = line()
      stub_lines([prepaid])

      stub(CreditGrants, :list_for_customer, fn _customer_id ->
        {:ok, [%{id: "credgr_1", metadata: %{"tuist_prepaid_invoice_line_id" => prepaid.id}}]}
      end)

      reject(&CreditGrants.create/1)

      assert {:ok, []} = Prepaid.grant_for_paid_invoice(invoice())
    end

    test "grants only the lines a partial failure left behind" do
      done = line()
      pending = line()
      stub_lines([done, pending])

      stub(CreditGrants, :list_for_customer, fn _customer_id ->
        {:ok, [%{id: "credgr_1", metadata: %{tuist_prepaid_invoice_line_id: done.id}}]}
      end)

      expect(CreditGrants, :create, fn attrs ->
        assert attrs.metadata["tuist_prepaid_invoice_line_id"] == pending.id
        {:ok, %{id: "credgr_2"}}
      end)

      assert {:ok, [%{id: "credgr_2"}]} = Prepaid.grant_for_paid_invoice(invoice())
    end

    test "keeps the grant owed when no runner price exists yet" do
      stub(Environment, :stripe_prices, fn -> %{"runners" => %{}} end)
      stub_lines([line()])
      reject(&CreditGrants.create/1)

      assert {:error, :no_runner_prices_configured} = Prepaid.grant_for_paid_invoice(invoice())
    end

    test "refuses to fund a grant from a line that charged nothing" do
      stub_lines([line(%{amount: 0})])
      reject(&CreditGrants.create/1)

      assert {:error, {:invalid_line_amount, 0}} = Prepaid.grant_for_paid_invoice(invoice())
    end

    test "propagates a failure to read the invoice's lines" do
      stub(Invoices, :list_lines, fn _invoice_id -> {:error, :timeout} end)
      reject(&CreditGrants.create/1)

      assert {:error, :timeout} = Prepaid.grant_for_paid_invoice(invoice())
    end
  end

  describe "quote_minutes/1" do
    test "prices baseline minutes at the prepaid rate and funds them at the gross one" do
      quoted = Prepaid.quote_minutes(10_000)

      # 10,000 x $0.06 invoiced, funded 1.25x, which buys back exactly
      # 10,000 minutes at the $0.075 on-demand rate usage is reported at.
      assert quoted.invoiced == Money.new(60_000, :USD)
      assert quoted.granted == Money.new(75_000, :USD)
      assert quoted.funding_ratio_bp == 12_500
      assert quoted.minutes == 10_000
    end

    test "the granted credit buys back the minutes sold" do
      # granted / on-demand rate, in tenths of a cent, is the minutes sold.
      # Exact whenever the amounts land on whole cents, which any
      # realistic purchase does.
      for minutes <- [250, 10_000, 1_000_000] do
        quoted = Prepaid.quote_minutes(minutes)
        assert div(quoted.granted.amount * 10, 75) == minutes
      end
    end

    test "never over-grants when the arithmetic falls between cents" do
      # A single minute costs 6 cents and would fund 7.5, which integer
      # cents cannot hold. Truncating keeps the shortfall under one cent
      # and never hands out credit that was not paid for.
      quoted = Prepaid.quote_minutes(1)

      assert quoted.invoiced == Money.new(6, :USD)
      assert quoted.granted == Money.new(7, :USD)
    end
  end

  describe "bill_prepaid_minutes/3" do
    test "adds a pending invoice item so the charge rides the next monthly bill" do
      expect(Stripe.Invoiceitem, :create, fn params ->
        assert params.customer == "cus_bill"
        assert params.amount == 60_000
        assert params.currency == "usd"
        assert params.metadata["tuist_prepaid_runners"] == "linux,macos"
        assert params.description =~ "10000"
        {:ok, %{id: "ii_1"}}
      end)

      assert {:ok, %{id: "ii_1"}} =
               Prepaid.bill_prepaid_minutes(%Account{customer_id: "cus_bill"}, 10_000)
    end

    test "can be scoped to one platform" do
      expect(Stripe.Invoiceitem, :create, fn params ->
        assert params.metadata["tuist_prepaid_runners"] == "macos"
        {:ok, %{id: "ii_1"}}
      end)

      assert {:ok, _item} =
               Prepaid.bill_prepaid_minutes(%Account{customer_id: "cus_bill"}, 10_000, platforms: [:macos])
    end

    test "grants nothing on its own, since the money has not arrived" do
      stub(Stripe.Invoiceitem, :create, fn _params -> {:ok, %{id: "ii_1"}} end)
      reject(&CreditGrants.create/1)

      assert {:ok, _item} = Prepaid.bill_prepaid_minutes(%Account{customer_id: "cus_bill"}, 10_000)
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
