defmodule Tuist.Runners.PrepaidTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Billing
  alias Tuist.Billing.CreditGrants
  alias Tuist.Billing.Invoices
  alias Tuist.Billing.Subscription
  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.Runners.Prepaid

  @macos_price "price_runner_macos"
  @linux_price "price_runner_linux"
  @prepaid_price "price_runner_prepaid_minutes"

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

    # Every grant is dated from the account's billing period, so the
    # tests that are not about expiry still need one to exist.
    stub(Accounts, :get_account_from_customer_id, fn _id -> {:ok, %Account{id: 1}} end)

    stub(Billing, :current_billing_period, fn _account ->
      {~U[2026-08-01 00:00:00Z], ~U[2026-09-01 00:00:00Z]}
    end)

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
  defp prepaid_grant(id, item_id) do
    %{
      id: id,
      voided_at: nil,
      metadata: %{"tuist_runner_credit" => "prepaid", "tuist_prepaid_invoice_line_id" => item_id},
      amount: %{type: "monetary", monetary: %{currency: "usd", value: 750_000}},
      expires_at: nil
    }
  end

  defp stub_account_period(period_end) do
    stub(Accounts, :get_account_from_customer_id, fn _id -> {:ok, %Account{id: 1}} end)
    stub(Billing, :current_billing_period, fn _account -> {DateTime.add(period_end, -30, :day), period_end} end)
  end

  defp stub_lines(lines) do
    stub(Invoices, :list_lines, fn _invoice_id -> {:ok, lines} end)
  end

  defp stub_prices_with_prepaid do
    stub(Environment, :stripe_prices, fn ->
      %{
        "runners" => %{
          "runner_macos_compute_unit_milliseconds" => @macos_price,
          "runner_linux_compute_unit_milliseconds" => @linux_price
        },
        "runner_prepaid_minutes" => @prepaid_price
      }
    end)
  end

  # The line a renewal invoice carries for the standing prepaid item. It is
  # a subscription line, so it carries the subscription's metadata rather
  # than any prepaid marker, and is recognised by its price instead.
  defp renewal_line(overrides \\ %{}) do
    Map.merge(
      %{
        id: "il_#{System.unique_integer([:positive])}",
        amount: 36_000,
        metadata: %{},
        price: %{id: @prepaid_price},
        period: %{
          start: DateTime.to_unix(~U[2026-09-21 01:29:59Z]),
          end: DateTime.to_unix(~U[2026-10-21 01:29:59Z])
        }
      },
      overrides
    )
  end

  defp subscription_item(id, price_id, quantity, interval \\ "month") do
    %{id: id, quantity: quantity, price: %{id: price_id, recurring: %{interval: interval, interval_count: 1}}}
  end

  defp stub_standing_subscription(items) do
    stub(Billing, :get_current_active_subscription, fn _account -> %Subscription{subscription_id: "sub_standing"} end)
    stub(Stripe.Subscription, :retrieve, fn "sub_standing" -> {:ok, %{id: "sub_standing", items: %{data: items}}} end)
  end

  defp standing_account(attrs \\ %{}), do: struct(%Account{id: 7, customer_id: "cus_standing"}, attrs)

  describe "grant_for_invoice/1" do
    test "does nothing for an invoice with no prepaid line" do
      stub_lines([line(%{metadata: %{}}), line(%{metadata: nil})])
      reject(&CreditGrants.create/1)

      assert {:ok, :not_prepaid} = Prepaid.grant_for_invoice(invoice())
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

      assert {:ok, [%{id: "credgr_1"}]} = Prepaid.grant_for_invoice(invoice)
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

      assert {:ok, grants} = Prepaid.grant_for_invoice(invoice())
      assert length(grants) == 2
    end

    test "narrows the scope to one platform when the line asks for it" do
      stub_lines([line(%{metadata: %{"tuist_prepaid_runners" => "macos"}})])

      expect(CreditGrants, :create, fn attrs ->
        assert attrs.price_ids == [@macos_price]
        {:ok, %{id: "credgr_1"}}
      end)

      assert {:ok, [_grant]} = Prepaid.grant_for_invoice(invoice())
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
                 Prepaid.grant_for_invoice(invoice()),
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

      assert {:ok, [_grant]} = Prepaid.grant_for_invoice(invoice())
    end

    test "does not grant again for an item already granted when it was billed" do
      # The line on the invoice is a different object from the invoice
      # item it came from, so matching on the line id alone would grant
      # the same minutes a second time a month later.
      stub_account_period(~U[2026-09-01 00:00:00Z])

      stub(CreditGrants, :list_for_customer, fn _customer_id ->
        {:ok, [%{metadata: %{"tuist_prepaid_invoice_line_id" => "ii_1"}}]}
      end)

      stub_lines([line(%{id: "il_9", invoice_item: "ii_1"})])
      reject(&CreditGrants.create/1)

      assert {:ok, []} = Prepaid.grant_for_invoice(invoice())
    end

    test "expires the grant just after the billing period it was bought in ends" do
      # Minutes belong to a month and do not roll over. Stripe applies a
      # grant only to an invoice whose period ends before the grant
      # expires, and the invoice that closes a period ends exactly when the
      # period does, so a grant expiring at that instant never paid for the
      # usage it was bought for. A few days past covers the invoice being
      # finalized, and is still long before the next period's invoice.
      now = ~U[2026-08-18 12:00:00Z]
      period_end = ~U[2026-09-01 00:00:00Z]
      stub(DateTime, :utc_now, fn -> now end)
      stub_account_period(period_end)

      stub_lines([line()])

      expect(CreditGrants, :create, fn attrs ->
        assert attrs.expires_at == DateTime.add(period_end, 4, :day)
        {:ok, %{id: "credgr_1"}}
      end)

      assert {:ok, [_grant]} = Prepaid.grant_for_invoice(invoice())
    end

    test "stays monthly on a yearly enterprise term" do
      # Runner items ride the account's own subscription, so an annual
      # enterprise term reports a year-long period. Dating the grant from
      # it would hand that account a year of minutes to bank, which is
      # the accumulation monthly expiry exists to prevent.
      now = ~U[2026-08-18 12:00:00Z]
      stub(DateTime, :utc_now, fn -> now end)
      stub_account_period(~U[2027-08-01 00:00:00Z])

      stub_lines([line()])

      expect(CreditGrants, :create, fn attrs ->
        assert attrs.expires_at == DateTime.shift(now, month: 1)
        {:ok, %{id: "credgr_1"}}
      end)

      assert {:ok, [_grant]} = Prepaid.grant_for_invoice(invoice())
    end

    test "falls back to a month out when the account has no billing period" do
      # The money is already collected, so an account Stripe reports no
      # period for must still get its minutes. A month keeps the promise
      # monthly rather than stranding what was paid for.
      now = ~U[2026-08-18 12:00:00Z]
      stub(DateTime, :utc_now, fn -> now end)
      stub(Accounts, :get_account_from_customer_id, fn _id -> {:ok, %Account{id: 1}} end)
      stub(Billing, :current_billing_period, fn _account -> nil end)

      stub_lines([line()])

      expect(CreditGrants, :create, fn attrs ->
        assert attrs.expires_at == DateTime.shift(now, month: 1)
        {:ok, %{id: "credgr_1"}}
      end)

      assert {:ok, [_grant]} = Prepaid.grant_for_invoice(invoice())
    end

    test "ignores a legacy per-deal expiry carried in line metadata" do
      # Invoices raised before expiry became monthly still carry this
      # key. Honouring it would reintroduce a grant outliving its month.
      now = ~U[2026-08-18 12:00:00Z]
      period_end = ~U[2026-09-01 00:00:00Z]
      stub(DateTime, :utc_now, fn -> now end)
      stub_account_period(period_end)

      stub_lines([
        line(%{
          metadata: %{
            "tuist_prepaid_runners" => "true",
            "tuist_prepaid_runners_expires_in_days" => "90"
          }
        })
      ])

      expect(CreditGrants, :create, fn attrs ->
        assert attrs.expires_at == DateTime.add(period_end, 4, :day)
        {:ok, %{id: "credgr_1"}}
      end)

      assert {:ok, [_grant]} = Prepaid.grant_for_invoice(invoice())
    end

    test "rejects an unknown platform" do
      stub_lines([line(%{metadata: %{"tuist_prepaid_runners" => "windows"}})])
      reject(&CreditGrants.create/1)

      assert {:error, {:unknown_platform, "windows"}} = Prepaid.grant_for_invoice(invoice())
    end

    test "does not grant twice for the same line" do
      prepaid = line()
      stub_lines([prepaid])

      stub(CreditGrants, :list_for_customer, fn _customer_id ->
        {:ok, [%{id: "credgr_1", metadata: %{"tuist_prepaid_invoice_line_id" => prepaid.id}}]}
      end)

      reject(&CreditGrants.create/1)

      assert {:ok, []} = Prepaid.grant_for_invoice(invoice())
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

      assert {:ok, [%{id: "credgr_2"}]} = Prepaid.grant_for_invoice(invoice())
    end

    test "keeps the grant owed when no runner price exists yet" do
      stub(Environment, :stripe_prices, fn -> %{"runners" => %{}} end)
      stub_lines([line()])
      reject(&CreditGrants.create/1)

      assert {:error, :no_runner_prices_configured} = Prepaid.grant_for_invoice(invoice())
    end

    test "refuses to fund a grant from a line that charged nothing" do
      stub_lines([line(%{amount: 0})])
      reject(&CreditGrants.create/1)

      assert {:error, {:invalid_line_amount, 0}} = Prepaid.grant_for_invoice(invoice())
    end

    test "propagates a failure to read the invoice's lines" do
      stub(Invoices, :list_lines, fn _invoice_id -> {:error, :timeout} end)
      reject(&CreditGrants.create/1)

      assert {:error, :timeout} = Prepaid.grant_for_invoice(invoice())
    end
  end

  describe "grant_for_invoice/1 on a renewal carrying standing minutes" do
    setup do
      stub_prices_with_prepaid()
      stub(Tuist.Time, :utc_now, fn -> ~U[2026-09-21 02:30:00Z] end)
      :ok
    end

    test "grants the minutes the renewal billed, dated from the line's own period" do
      # The account's recorded period may still be the one that just closed
      # when the renewal is paid, so the grant is dated from the period the
      # line itself was billed for. The setup's account period ends on
      # September 1, which this must not use.
      invoice = invoice()
      renewal = renewal_line()
      usage = %{id: "il_usage", amount: 12_000, metadata: %{}, price: %{id: @macos_price}}

      stub_lines([usage, renewal])

      expect(CreditGrants, :create, fn attrs ->
        assert attrs.amount_cents == 45_000
        assert Enum.sort(attrs.price_ids) == Enum.sort([@macos_price, @linux_price])
        assert attrs.expires_at == ~U[2026-10-25 01:29:59Z]
        assert attrs.idempotency_key == "runner-prepaid-#{invoice.id}-#{renewal.id}"
        assert attrs.metadata["tuist_prepaid_invoice_line_id"] == renewal.id
        assert attrs.metadata["tuist_prepaid_paid_cents"] == "36000"
        {:ok, %{id: "credgr_1"}}
      end)

      assert {:ok, [%{id: "credgr_1"}]} = Prepaid.grant_for_invoice(invoice)
    end

    test "refuses a renewal whose period has already ended" do
      # A grant is effective from when it is created. Created after its line's
      # period, it misses the invoice closing that period and expires before
      # the next one, so it would never pay for anything.
      stub(Tuist.Time, :utc_now, fn -> ~U[2026-10-23 09:00:00Z] end)
      renewal = renewal_line()

      stub_lines([renewal])
      reject(&CreditGrants.create/1)

      assert {:error, {:standing_period_ended, line_id}} = Prepaid.grant_for_invoice(invoice())
      assert line_id == renewal.id
    end

    test "does not treat a line on another price as prepaid" do
      stub_lines([%{id: "il_usage", amount: 12_000, metadata: %{}, price: %{id: @macos_price}}])
      reject(&CreditGrants.create/1)

      assert {:ok, :not_prepaid} = Prepaid.grant_for_invoice(invoice())
    end

    test "does not grant a renewal a second time when the invoice is redelivered" do
      renewal = renewal_line()

      stub(CreditGrants, :list_for_customer, fn _customer_id ->
        {:ok, [%{metadata: %{"tuist_prepaid_invoice_line_id" => renewal.id}}]}
      end)

      stub_lines([renewal])
      reject(&CreditGrants.create/1)

      assert {:ok, []} = Prepaid.grant_for_invoice(invoice())
    end
  end

  describe "standing_minutes/1" do
    setup do
      stub_prices_with_prepaid()
      :ok
    end

    test "reads the minutes off the prepaid subscription item" do
      stub_standing_subscription([
        subscription_item("si_plan", "price_pro_flat", 1),
        subscription_item("si_prepaid", @prepaid_price, 6_000)
      ])

      assert {:ok, 6_000} = Prepaid.standing_minutes(standing_account())
    end

    test "reads zero when the subscription carries no prepaid item" do
      stub_standing_subscription([subscription_item("si_plan", "price_pro_flat", 1)])

      assert {:ok, 0} = Prepaid.standing_minutes(standing_account())
    end

    test "is unavailable without an active subscription" do
      stub(Billing, :get_current_active_subscription, fn _account -> nil end)
      reject(&Stripe.Subscription.retrieve/1)

      assert {:error, :no_subscription} = Prepaid.standing_minutes(standing_account())
    end

    test "is unavailable on a subscription that does not renew monthly" do
      # An item that renews monthly cannot sit on an annual subscription in
      # classic billing mode.
      stub_standing_subscription([subscription_item("si_plan", "price_enterprise_flat", 1, "year")])

      assert {:error, :not_monthly} = Prepaid.standing_minutes(standing_account())
    end

    test "is unavailable until the prepaid price is configured" do
      stub(Environment, :stripe_prices, fn -> %{"runners" => %{}} end)
      reject(&Stripe.Subscription.retrieve/1)

      assert {:error, :no_prepaid_price_configured} = Prepaid.standing_minutes(standing_account())
    end
  end

  describe "set_standing_minutes/2" do
    setup do
      stub_prices_with_prepaid()
      :ok
    end

    test "adds the prepaid item without prorating the cycle already running" do
      # No proration is what leaves the running cycle alone: the item is
      # billed for the first time on the next renewal, together with the
      # minutes it buys.
      stub_standing_subscription([subscription_item("si_plan", "price_pro_flat", 1)])

      expect(Stripe.Subscription, :update, fn "sub_standing", params ->
        assert params.items == [%{price: @prepaid_price, quantity: 6_000}]
        assert params.proration_behavior == "none"
        {:ok, %{id: "sub_standing"}}
      end)

      assert {:ok, 6_000} = Prepaid.set_standing_minutes(standing_account(), 6_000)
    end

    test "changes the quantity of the prepaid item the subscription already carries" do
      stub_standing_subscription([
        subscription_item("si_plan", "price_pro_flat", 1),
        subscription_item("si_prepaid", @prepaid_price, 4_000)
      ])

      expect(Stripe.Subscription, :update, fn "sub_standing", params ->
        assert params.items == [%{id: "si_prepaid", quantity: 6_000}]
        assert params.proration_behavior == "none"
        {:ok, %{id: "sub_standing"}}
      end)

      assert {:ok, 6_000} = Prepaid.set_standing_minutes(standing_account(), 6_000)
    end

    test "leaves the subscription alone when it already carries that many minutes" do
      stub_standing_subscription([subscription_item("si_prepaid", @prepaid_price, 6_000)])
      reject(&Stripe.Subscription.update/2)

      assert {:ok, 6_000} = Prepaid.set_standing_minutes(standing_account(), 6_000)
    end

    test "removes the prepaid item when set to zero" do
      stub_standing_subscription([
        subscription_item("si_plan", "price_pro_flat", 1),
        subscription_item("si_prepaid", @prepaid_price, 6_000)
      ])

      expect(Stripe.Subscription, :update, fn "sub_standing", params ->
        assert params.items == [%{id: "si_prepaid", deleted: true}]
        assert params.proration_behavior == "none"
        {:ok, %{id: "sub_standing"}}
      end)

      assert {:ok, 0} = Prepaid.set_standing_minutes(standing_account(), 0)
    end

    test "has nothing to remove when zero is set on a subscription without the item" do
      stub_standing_subscription([subscription_item("si_plan", "price_pro_flat", 1)])
      reject(&Stripe.Subscription.update/2)

      assert {:ok, 0} = Prepaid.set_standing_minutes(standing_account(), 0)
    end

    test "refuses a subscription that does not renew monthly" do
      stub_standing_subscription([subscription_item("si_plan", "price_enterprise_flat", 1, "year")])
      reject(&Stripe.Subscription.update/2)

      assert {:error, :not_monthly} = Prepaid.set_standing_minutes(standing_account(), 6_000)
    end

    test "refuses an account on a runner trial" do
      # A trial carries no runner items, so its usage is never invoiced and
      # the credit the item buys would have nothing to pay for.
      stub_standing_subscription([subscription_item("si_plan", "price_pro_flat", 1)])
      reject(&Stripe.Subscription.update/2)

      account = standing_account(%{runner_trial_started_at: ~U[2026-09-01 00:00:00Z]})

      assert {:error, :on_runner_trial} = Prepaid.set_standing_minutes(account, 6_000)
    end

    test "refuses until the prepaid price is configured" do
      stub(Environment, :stripe_prices, fn -> %{"runners" => %{}} end)
      reject(&Stripe.Subscription.update/2)

      assert {:error, :no_prepaid_price_configured} = Prepaid.set_standing_minutes(standing_account(), 6_000)
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
      stub(CreditGrants, :create, fn _attrs -> {:ok, %{id: "credgr_1"}} end)

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
      stub(CreditGrants, :create, fn _attrs -> {:ok, %{id: "credgr_1"}} end)

      expect(Stripe.Invoiceitem, :create, fn params ->
        assert params.metadata["tuist_prepaid_runners"] == "macos"
        {:ok, %{id: "ii_1"}}
      end)

      assert {:ok, _item} =
               Prepaid.bill_prepaid_minutes(%Account{customer_id: "cus_bill"}, 10_000, platforms: [:macos])
    end

    test "grants the minutes up front rather than waiting for the invoice" do
      stub(Stripe.Invoiceitem, :create, fn _params -> {:ok, %{id: "ii_1"}} end)
      stub_account_period(~U[2026-09-01 00:00:00Z])

      expect(CreditGrants, :create, fn attrs ->
        assert attrs.customer_id == "cus_bill"
        # The funded amount, not the invoiced one: 60_000 paid buys
        # 75_000 of credit at the 1.25x default.
        assert attrs.amount_cents == 75_000
        assert attrs.category == "paid"
        assert Enum.sort(attrs.price_ids) == Enum.sort([@macos_price, @linux_price])
        assert attrs.expires_at == ~U[2026-09-05 00:00:00Z]
        # Keyed on the invoice item, because there is no invoice yet.
        assert attrs.idempotency_key == "runner-prepaid-item-ii_1"
        assert attrs.metadata["tuist_prepaid_invoice_line_id"] == "ii_1"
        {:ok, %{id: "credgr_1"}}
      end)

      assert {:ok, %{id: "ii_1"}} =
               Prepaid.bill_prepaid_minutes(%Account{customer_id: "cus_bill"}, 10_000)
    end

    test "withdraws the charge when granting fails" do
      # Leaving the charge behind would bill the customer for minutes
      # they never got, and a retry would add a second charge beside the
      # first. Withdrawing it means a failed sale costs them nothing.
      stub(Stripe.Invoiceitem, :create, fn _params -> {:ok, %{id: "ii_1"}} end)
      stub_account_period(~U[2026-09-01 00:00:00Z])
      stub(CreditGrants, :create, fn _attrs -> {:error, :stripe_down} end)

      expect(Stripe.Invoiceitem, :delete, fn "ii_1" -> {:ok, %{id: "ii_1", deleted: true}} end)

      # The original failure is what ops needs to see, not the cleanup.
      assert {:error, :stripe_down} =
               Prepaid.bill_prepaid_minutes(%Account{customer_id: "cus_bill"}, 10_000)
    end

    test "reports the grant failure even when the charge cannot be withdrawn" do
      # The invoice.paid worker is the backstop for the charge that got
      # away, so the useful thing to surface here is still why the grant
      # failed.
      stub(Stripe.Invoiceitem, :create, fn _params -> {:ok, %{id: "ii_1"}} end)
      stub_account_period(~U[2026-09-01 00:00:00Z])
      stub(CreditGrants, :create, fn _attrs -> {:error, :stripe_down} end)
      stub(Stripe.Invoiceitem, :delete, fn "ii_1" -> {:error, :also_down} end)

      assert {:error, :stripe_down} =
               Prepaid.bill_prepaid_minutes(%Account{customer_id: "cus_bill"}, 10_000)
    end
  end

  describe "set_minutes/3" do
    test "grants the target when the account holds none" do
      stub(CreditGrants, :list_for_customer, fn _customer_id -> {:ok, []} end)
      stub_account_period(~U[2026-09-01 00:00:00Z])

      expect(Stripe.Invoiceitem, :create, fn params ->
        assert params.amount == 60_000
        {:ok, %{id: "ii_1"}}
      end)

      expect(CreditGrants, :create, fn attrs ->
        assert attrs.amount_cents == 75_000
        {:ok, %{id: "credgr_1"}}
      end)

      assert {:ok, _} = Prepaid.set_minutes(%Account{customer_id: "cus_set"}, 10_000)
    end

    test "replaces what is there rather than stacking another grant on top" do
      # Setting is not adding: the account ends up with the number typed,
      # held as one grant, not that many more minutes than before.
      stub(CreditGrants, :list_for_customer, fn _customer_id ->
        {:ok, [prepaid_grant("credgr_old", "ii_old")]}
      end)

      stub_account_period(~U[2026-09-01 00:00:00Z])

      expect(Stripe.Invoiceitem, :delete, fn "ii_old" -> {:ok, %{id: "ii_old", deleted: true}} end)
      expect(CreditGrants, :void, fn "credgr_old" -> {:ok, %{id: "credgr_old"}} end)

      expect(Stripe.Invoiceitem, :create, fn params ->
        assert params.amount == 600
        {:ok, %{id: "ii_new"}}
      end)

      expect(CreditGrants, :create, fn attrs ->
        assert attrs.amount_cents == 750
        {:ok, %{id: "credgr_new"}}
      end)

      assert {:ok, _} = Prepaid.set_minutes(%Account{customer_id: "cus_set"}, 100)
    end

    test "sets through a charge that has already been invoiced" do
      # Stripe refuses to delete an invoice item once it is on an
      # invoice. That is not a reason to leave the account holding
      # minutes nobody asked it to hold: the set goes through and the
      # charge stands, to be refunded separately if it needs to be.
      stub(CreditGrants, :list_for_customer, fn _customer_id ->
        {:ok, [prepaid_grant("credgr_paid", "ii_paid")]}
      end)

      stub_account_period(~U[2026-09-01 00:00:00Z])

      expect(Stripe.Invoiceitem, :delete, fn "ii_paid" ->
        {:error, %Stripe.Error{source: :stripe, code: :invalid_request_error, message: "already invoiced"}}
      end)

      expect(CreditGrants, :void, fn "credgr_paid" -> {:ok, %{id: "credgr_paid"}} end)
      expect(Stripe.Invoiceitem, :create, fn _params -> {:ok, %{id: "ii_new"}} end)
      expect(CreditGrants, :create, fn _attrs -> {:ok, %{id: "credgr_new"}} end)

      assert {:ok, _} = Prepaid.set_minutes(%Account{customer_id: "cus_set"}, 100)
    end

    test "leaves alone the grants it already voided" do
      # A voided grant stays in Stripe's listing. Trying to void it again
      # is an error, and it used to take the whole set down with it: the
      # first set worked and every one after it did nothing.
      stub(CreditGrants, :list_for_customer, fn _customer_id ->
        {:ok,
         [
           %{prepaid_grant("credgr_spent", "ii_spent") | voided_at: 1_756_000_000},
           prepaid_grant("credgr_live", "ii_live")
         ]}
      end)

      stub_account_period(~U[2026-09-01 00:00:00Z])

      # Only the live one: `expect` fails the test on a second call.
      expect(Stripe.Invoiceitem, :delete, fn "ii_live" -> {:ok, %{deleted: true}} end)
      expect(CreditGrants, :void, fn "credgr_live" -> {:ok, %{id: "credgr_live"}} end)

      expect(Stripe.Invoiceitem, :create, fn _params -> {:ok, %{id: "ii_new"}} end)
      expect(CreditGrants, :create, fn _attrs -> {:ok, %{id: "credgr_new"}} end)

      assert {:ok, _} = Prepaid.set_minutes(%Account{customer_id: "cus_set"}, 3_000)
    end

    test "keeps the minutes it was set to when withdrawing the old ones fails" do
      # Withdrawing first meant a failure part-way emptied the account
      # and granted nothing, so a set that errored destroyed minutes the
      # customer had paid for. Granting first fails the other way: the
      # account holds too much rather than nothing, and a retry
      # converges on the figure asked for.
      stub(CreditGrants, :list_for_customer, fn _customer_id ->
        {:ok, [prepaid_grant("credgr_old", "ii_old")]}
      end)

      stub_account_period(~U[2026-09-01 00:00:00Z])
      stub(Stripe.Invoiceitem, :delete, fn _id -> {:ok, %{deleted: true}} end)

      expect(Stripe.Invoiceitem, :create, fn _params -> {:ok, %{id: "ii_new"}} end)
      expect(CreditGrants, :create, fn _attrs -> {:ok, %{id: "credgr_new"}} end)
      expect(CreditGrants, :void, fn "credgr_old" -> {:error, :stripe_down} end)

      assert {:error, :stripe_down} = Prepaid.set_minutes(%Account{customer_id: "cus_set"}, 3_000)
    end

    test "clears the balance when set to zero" do
      stub(CreditGrants, :list_for_customer, fn _customer_id ->
        {:ok, [prepaid_grant("credgr_old", "ii_old")]}
      end)

      expect(Stripe.Invoiceitem, :delete, fn "ii_old" -> {:ok, %{deleted: true}} end)
      expect(CreditGrants, :void, fn "credgr_old" -> {:ok, %{id: "credgr_old"}} end)

      reject(&Stripe.Invoiceitem.create/1)
      reject(&CreditGrants.create/1)

      assert {:ok, _} = Prepaid.set_minutes(%Account{customer_id: "cus_set"}, 0)
    end
  end

  describe "refresh_balance/1" do
    test "writes the cache even when nothing is left" do
      # summarize/1 answers nil for an account holding nothing, and the
      # refresh used to skip writing nil. The stale entry survived, the
      # page went on serving the figure from before the clear, and
      # setting zero looked impossible.
      stub(CreditGrants, :list_for_customer, fn _customer_id -> {:ok, []} end)

      expect(KeyValueStore, :put, fn _key, value, _opts ->
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
      # $750 of credit buys 10,000 minutes at the $0.075 standard rate.
      assert balance.granted_minutes == 10_000
    end
  end
end
