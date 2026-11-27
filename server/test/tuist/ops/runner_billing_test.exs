defmodule Tuist.Ops.RunnerBillingTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Billing.CreditGrants
  alias Tuist.Environment
  alias Tuist.Ops.RunnerBilling
  alias Tuist.Runners.PrepaidActivation
  alias Tuist.Runners.PrepaidTopUp
  alias Tuist.Runners.Trials
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  setup do
    now = ~U[2026-11-16 10:00:00Z]
    stub(DateTime, :utc_now, fn -> now end)
    stub(Date, :utc_today, fn -> ~D[2026-11-16] end)
    customer = "cus_#{System.unique_integer([:positive])}"
    account = AccountsFixtures.organization_fixture(customer_id: customer, preload: [:account]).account
    account = account |> change(runner_trial_started_at: ~U[2026-08-25 00:00:00Z]) |> Repo.update!()

    BillingFixtures.subscription_fixture(
      account_id: account.id,
      subscription_id: "sub_prepaid",
      plan: :enterprise,
      current_period_start: ~U[2026-10-21 08:48:39Z],
      current_period_end: ~U[2026-11-21 08:48:39Z]
    )

    price = %{
      id: "price_macos",
      currency: "usd",
      billing_scheme: "tiered",
      tiers_mode: "graduated",
      recurring: %{interval: "month", interval_count: 1, usage_type: "metered"},
      tiers: [
        %{up_to: 6_000_000, unit_amount: 0, flat_amount: nil},
        %{up_to: nil, unit_amount: nil, unit_amount_decimal: "0.000083333333", flat_amount: nil}
      ]
    }

    linux_price = %{
      price
      | id: "price_linux",
        tiers: [
          %{up_to: 150_000_000, unit_amount: 0, flat_amount: nil},
          %{up_to: nil, unit_amount: nil, unit_amount_decimal: "0.000004", flat_amount: nil}
        ]
    }

    cache_prices = %{
      "price_cache_egress" => %{
        price
        | id: "price_cache_egress",
          tiers: [
            %{up_to: 100_000, unit_amount: 0, flat_amount: nil},
            %{up_to: nil, unit_amount: nil, unit_amount_decimal: "0.01", flat_amount: nil}
          ]
      },
      "price_cache_requests" => %{
        price
        | id: "price_cache_requests",
          tiers: [
            %{up_to: 1_000_000, unit_amount: 0, flat_amount: nil},
            %{up_to: nil, unit_amount: nil, unit_amount_decimal: "0.001", flat_amount: nil}
          ]
      }
    }

    seat = %{
      id: "si_seat",
      quantity: 0,
      price: %{id: "price_seat", recurring: %{interval: "month", interval_count: 1, usage_type: "licensed"}}
    }

    subscription = %{
      id: "sub_prepaid",
      customer: customer,
      billing_mode: %{type: "classic"},
      status: "active",
      cancel_at: nil,
      cancel_at_period_end: false,
      schedule: nil,
      items: %{data: [seat]},
      current_period_start: DateTime.to_unix(~U[2026-10-21 08:48:39Z]),
      current_period_end: DateTime.to_unix(~U[2026-11-21 08:48:39Z])
    }

    stripe =
      start_supervised!(
        {Agent,
         fn ->
           %{
             subscription: subscription,
             grants: [],
             schedule: nil,
             fail_schedule: false,
             fail_update: false,
             ambiguous_grant: false,
             fail_snapshot: false,
             creates: 0
           }
         end}
      )

    stub(Environment, :stripe_prices, fn ->
      %{
        "runners" => %{
          "runner_macos_compute_unit_milliseconds" => price.id,
          "runner_linux_compute_unit_milliseconds" => linux_price.id
        },
        "usage_meters" => %{
          "cache_egress_megabytes" => "price_cache_egress",
          "cache_requests" => "price_cache_requests",
          "passing_test_cases" => "price_test_cases"
        }
      }
    end)

    prices = Map.merge(cache_prices, %{"price_macos" => price, "price_linux" => linux_price})
    stub(Stripe.Price, :retrieve, fn id, %{expand: ["tiers"]} -> {:ok, Map.fetch!(prices, id)} end)

    stub(Stripe.Invoice, :retrieve, fn "in_order" ->
      {:ok, %{customer: customer, currency: "usd", subtotal: 625_000, status: "draft"}}
    end)

    stub(Stripe.Subscription, :retrieve, fn "sub_prepaid" -> {:ok, Agent.get(stripe, & &1.subscription)} end)

    stub(Stripe.API, :request, fn %{}, :get, "/v1/subscriptions/sub_prepaid", _, [] ->
      raw = stripe |> Agent.get(& &1.subscription) |> JSON.encode!() |> JSON.decode!()
      {:ok, Map.put(raw, "object", "subscription")}
    end)

    stub(Stripe.Subscription, :update, fn "sub_prepaid", %{items: items, proration_behavior: "none"} ->
      Agent.get_and_update(stripe, fn state ->
        added =
          Enum.map(items, fn
            %{price: "price_macos"} -> %{id: "si_macos", price: price, quantity: nil}
            %{price: "price_linux"} -> %{id: "si_linux", price: linux_price, quantity: nil}
            %{price: "price_cache_" <> meter = id} -> %{id: "si_cache_#{meter}", price: cache_prices[id], quantity: nil}
          end)

        subscription = %{state.subscription | items: %{data: state.subscription.items.data ++ added}}
        {{:ok, subscription}, %{state | subscription: subscription}}
      end)
    end)

    stub(Stripe.Request, :make_request, fn request ->
      Agent.get_and_update(stripe, &stripe_request(request, &1))
    end)

    {:ok, state} = RunnerBilling.get(account.id)

    params = %{
      "paid_cents" => 625_000,
      "credit_multiplier" => "1.1112",
      "platforms" => ["macos", "linux"],
      "starts_on" => "2026-10-15",
      "expires_on" => "2027-05-31",
      "invoice_id" => "in_order",
      "expected_revision" => state.revision,
      "reason" => "Apply signed runner order",
      "change_id" => Ecto.UUID.generate(),
      "actor" => %{"id" => Ecto.UUID.generate(), "email" => "operator@tuist.dev"},
      "interface" => "mcp"
    }

    %{account: account, stripe: stripe, params: params, seat: seat, now: now, price: price, prices: prices}
  end

  test "activates one shared compute pool and strict final period without replacing SaaS", context do
    %{account: account, stripe: stripe, params: params, seat: seat, now: now} = context
    assert {:ok, result} = RunnerBilling.activate(account.id, params, %{name: "atlas"})
    assert result.activation.status == "applied"
    assert result.runner_trial.ended_at == now
    refute result.runner_trial.active
    refute Trials.on_trial?(Repo.reload!(account))

    state = Agent.get(stripe, & &1)
    assert state.creates == 1
    assert [grant] = state.grants
    assert grant.amount.monetary == %{currency: "usd", value: 694_500}
    assert Enum.sort(grant.applicability_config.scope.prices) == [%{id: "price_linux"}, %{id: "price_macos"}]
    assert grant.metadata["tuist_prepaid_invoice_id"] == "in_order"
    assert grant.metadata["tuist_prepaid_expires_on"] == "2027-05-31"
    assert grant.expires_at == DateTime.to_unix(~U[2027-06-05 00:00:00Z])
    assert hd(state.subscription.items.data) == seat

    assert Enum.sort(Enum.map(state.subscription.items.data, & &1.price.id)) == [
             "price_linux",
             "price_macos",
             "price_seat"
           ]

    assert [during, after_term] = state.schedule.phases
    cutoff = DateTime.to_unix(~U[2027-06-01 00:00:00Z])
    assert during.end_date == cutoff
    assert after_term.start_date == cutoff
    assert after_term.billing_cycle_anchor == "phase_start"
    assert after_term.end_date == DateTime.to_unix(~U[2027-07-01 00:00:00Z])
    assert during.items == after_term.items
    assert during.collection_method == "send_invoice"
    assert during.invoice_settings.days_until_due == 30
    assert during.proration_behavior == "none"
    assert state.schedule.end_behavior == "release"
    refute Map.has_key?(during, :add_invoice_items)
    refute Map.has_key?(after_term, :add_invoice_items)

    recorded = Repo.get_by!(PrepaidActivation, change_id: params["change_id"])
    assert recorded.request == params
    assert recorded.principal == %{"name" => "atlas"}
    assert recorded.grant_id == grant.id
    assert recorded.subscription_schedule_id == state.schedule.id
    assert recorded.after["activation"]["status"] == "applied"
    assert recorded.after["activation"]["subscription_schedule_id"] == state.schedule.id

    # A replay returns the original result without touching Stripe, even
    # though activation changed the revision and the trial is already over.
    reject(&CreditGrants.list_for_customer/1)
    assert {:ok, replay} = RunnerBilling.activate(account.id, params, %{name: "atlas"})
    assert replay == recorded.after
    assert {:error, :change_id_conflict} = RunnerBilling.activate(account.id, Map.put(params, "paid_cents", 1), %{})
  end

  test "a pool covering cache usage pays for it from the same grant at the same multiplier", context do
    %{account: account, stripe: stripe, params: params} = context
    params = Map.put(params, "covers_cache", true)

    assert {:ok, result} = RunnerBilling.activate(account.id, params, %{name: "atlas"})
    assert result.activation.status == "applied"

    state = Agent.get(stripe, & &1)
    assert state.creates == 1
    assert [grant] = state.grants
    assert grant.amount.monetary == %{currency: "usd", value: 694_500}
    assert grant.metadata["tuist_prepaid_covers_cache"] == "true"

    assert Enum.sort(grant.applicability_config.scope.prices) == [
             %{id: "price_cache_egress"},
             %{id: "price_cache_requests"},
             %{id: "price_linux"},
             %{id: "price_macos"}
           ]

    # Test insights stay off the subscription; the schedule keeps the cache items.
    subscription_prices = Enum.map(state.subscription.items.data, & &1.price.id)

    assert Enum.sort(subscription_prices) ==
             ~w(price_cache_egress price_cache_requests price_linux price_macos price_seat)

    assert [during, after_term] = state.schedule.phases
    assert Enum.sort(Enum.map(during.items, & &1.price)) == Enum.sort(subscription_prices)
    assert during.items == after_term.items

    # A replay after a failure resumes without granting or adding items twice.
    reject(&CreditGrants.list_for_customer/1)
    assert {:ok, replay} = RunnerBilling.activate(account.id, params, %{name: "atlas"})
    assert replay["activation"]["status"] == "applied"
  end

  test "a failure after the grant resumes a cache-covering pool without granting twice", context do
    %{account: account, stripe: stripe, params: params} = context
    params = Map.put(params, "covers_cache", true)
    Agent.update(stripe, &%{&1 | fail_schedule: true})
    assert {:error, :stripe_request_failed} = RunnerBilling.activate(account.id, params, %{})

    Agent.update(stripe, &%{&1 | fail_schedule: false})
    assert {:ok, state} = RunnerBilling.activate(account.id, params, %{})
    assert state.activation.status == "applied"
    assert Agent.get(stripe, & &1.creates) == 1
    assert Enum.count(Agent.get(stripe, & &1.subscription.items.data), &String.starts_with?(&1.id, "si_cache_")) == 2
  end

  test "pools cover cache usage only when asked, and only at the list rates", context do
    %{account: account, stripe: stripe, params: params, prices: prices} = context

    for covers_cache <- ["true", 1, nil] do
      assert {:error, :invalid_request} =
               RunnerBilling.activate(account.id, Map.put(params, "covers_cache", covers_cache), %{})
    end

    # Cache Prices already on a subscription are another service's paid items
    # unless the pool covers them.
    Agent.update(stripe, fn state ->
      cache_item = %{id: "si_cache_egress", price: prices["price_cache_egress"], quantity: nil}
      update_in(state.subscription.items.data, &(&1 ++ [cache_item]))
    end)

    assert {:error, :runner_only_subscription_required} = RunnerBilling.activate(account.id, params, %{})

    # A cache Price charging more than `UsagePricing` quotes.
    prices =
      update_in(prices["price_cache_egress"].tiers, fn [free, paid] -> [free, %{paid | unit_amount_decimal: "0.02"}] end)

    stub(Stripe.Price, :retrieve, fn id, _ -> {:ok, Map.fetch!(prices, id)} end)

    assert {:error, :cache_price_mismatch} =
             RunnerBilling.activate(account.id, Map.put(params, "covers_cache", true), %{})

    assert Agent.get(stripe, & &1.creates) == 0
    assert Trials.on_trial?(Repo.reload!(account))
  end

  test "failed schedule retains the grant and trial checkpoint and resumes without granting twice", context do
    %{account: account, stripe: stripe, params: params} = context
    Agent.update(stripe, &%{&1 | fail_schedule: true})
    assert {:error, :stripe_request_failed} = RunnerBilling.activate(account.id, params, %{})
    assert {:ok, state} = RunnerBilling.get(account.id)
    assert state.activation.status == "pending"
    assert state.activation.grant_id == "credgr_order"
    refute state.runner_trial.active
    trial_end = state.runner_trial.ended_at

    Agent.update(stripe, &%{&1 | fail_schedule: false})
    assert {:ok, state} = RunnerBilling.activate(account.id, params, %{})
    assert state.activation.status == "applied"
    assert state.runner_trial.ended_at == trial_end
    assert Agent.get(stripe, & &1.creates) == 1
  end

  test "reconciles an accepted grant after a lost response without charging trial usage", context do
    %{account: account, stripe: stripe, params: params} = context
    Agent.update(stripe, &%{&1 | ambiguous_grant: true})
    assert {:error, :stripe_request_failed} = RunnerBilling.activate(account.id, params, %{})
    assert Trials.on_trial?(Repo.reload!(account))
    assert {:ok, _} = RunnerBilling.activate(account.id, params, %{})
    assert Agent.get(stripe, & &1.creates) == 1
  end

  test "resumes an untagged schedule only through Stripe's original idempotent create response", context do
    %{account: account, stripe: stripe, params: params} = context
    Agent.update(stripe, &%{&1 | fail_update: true})
    assert {:error, :stripe_request_failed} = RunnerBilling.activate(account.id, params, %{})
    assert Agent.get(stripe, & &1.schedule.metadata) == %{}
    Agent.update(stripe, &%{&1 | fail_update: false})
    assert {:ok, state} = RunnerBilling.activate(account.id, params, %{})
    assert state.activation.subscription_schedule_id == "sub_sched_order"
    assert Agent.get(stripe, & &1.creates) == 1
  end

  test "a failed final read stays pending and an identical replay returns a complete result", context do
    %{account: account, stripe: stripe, params: params} = context
    Agent.update(stripe, &%{&1 | fail_snapshot: true})
    assert {:error, :stripe_request_failed} = RunnerBilling.activate(account.id, params, %{})
    assert Repo.get_by!(PrepaidActivation, change_id: params["change_id"]).status == "pending"
    assert {:ok, state} = RunnerBilling.activate(account.id, params, %{})
    assert state.activation.status == "applied"
    assert {:ok, replay} = RunnerBilling.activate(account.id, params, %{})
    assert replay["activation"]["status"] == "applied"
    assert Agent.get(stripe, & &1.creates) == 1
  end

  test "rejects overlapping pools without granting or ending another trial", context do
    %{account: account, stripe: stripe, params: params} = context
    assert {:ok, _} = RunnerBilling.activate(account.id, params, %{})
    assert {:ok, current} = RunnerBilling.get(account.id)
    next = Map.merge(params, %{"change_id" => Ecto.UUID.generate(), "expected_revision" => current.revision})
    assert {:error, :prepaid_pool_exists} = RunnerBilling.activate(account.id, next, %{})
    assert Agent.get(stripe, & &1.creates) == 1
  end

  test "rejects a stale revision, mismatched invoice and malformed inputs before changing Stripe",
       context do
    %{account: account, stripe: stripe, params: params} = context

    assert {:error, :stale_revision} =
             RunnerBilling.activate(account.id, Map.put(params, "expected_revision", String.duplicate("0", 64)), %{})

    for override <- [
          %{"starts_on" => nil},
          %{"expires_on" => []},
          %{"credit_multiplier" => "NaN"},
          %{"platforms" => ["macos", "macos"]},
          %{"interface" => "worker"},
          %{"extra" => 1}
        ] do
      assert {:error, :invalid_request} = RunnerBilling.activate(account.id, Map.merge(params, override), %{})
    end

    stub(Stripe.Invoice, :retrieve, fn _ ->
      {:ok, %{customer: "cus_someone_else", currency: "usd", subtotal: 625_000, status: "draft"}}
    end)

    assert {:error, :invoice_does_not_match} = RunnerBilling.activate(account.id, params, %{})
    assert Agent.get(stripe, & &1.creates) == 0
    assert Trials.on_trial?(Repo.reload!(account))
  end

  test "refuses to move paid SaaS items or use a retired higher runner rate", context do
    %{account: account, stripe: stripe, params: params} = context

    Agent.update(stripe, fn state ->
      put_in(state.subscription.items.data, [%{hd(state.subscription.items.data) | quantity: 7}])
    end)

    assert {:error, :runner_only_subscription_required} = RunnerBilling.activate(account.id, params, %{})

    Agent.update(stripe, fn state ->
      put_in(state.subscription.items.data, [%{hd(state.subscription.items.data) | quantity: 0}])
    end)

    stub(Stripe.Price, :retrieve, fn _, _ -> {:ok, %{tiers: []}} end)
    assert {:error, :runner_price_mismatch} = RunnerBilling.activate(account.id, params, %{})
    assert Agent.get(stripe, & &1.creates) == 0
  end

  test "rejects decimal flat fees and nonfree allowances rather than silently accepting them", context do
    %{account: account, stripe: stripe, params: params, price: price} = context
    [free, paid] = price.tiers

    for tiers <- [
          [Map.put(free, :unit_amount_decimal, "0.0001"), paid],
          [Map.put(free, :flat_amount_decimal, "0.5"), paid],
          [free, Map.put(paid, :flat_amount_decimal, "1.5")]
        ] do
      stub(Stripe.Price, :retrieve, fn _, _ -> {:ok, %{price | tiers: tiers}} end)
      assert {:error, :runner_price_mismatch} = RunnerBilling.activate(account.id, params, %{})
    end

    assert Agent.get(stripe, & &1.creates) == 0
  end

  test "rejects flexible billing before any grant because its anchor-reset invoicing differs", context do
    %{account: account, stripe: stripe, params: params} = context
    Agent.update(stripe, &put_in(&1.subscription.billing_mode.type, "flexible"))
    assert {:error, :classic_billing_required} = RunnerBilling.activate(account.id, params, %{})
    assert Agent.get(stripe, & &1.creates) == 0
    assert Trials.on_trial?(Repo.reload!(account))
  end

  test "rejects subscription discounts before granting or ending the trial", context do
    %{account: account, stripe: stripe, params: params} = context

    Agent.update(
      stripe,
      &Map.update!(&1, :subscription, fn subscription -> Map.put(subscription, :discounts, ["di_order"]) end)
    )

    assert {:error, :runner_only_subscription_required} = RunnerBilling.activate(account.id, params, %{})
    assert Agent.get(stripe, & &1.creates) == 0
    assert Trials.on_trial?(Repo.reload!(account))
  end

  describe "an order paid in instalments" do
    test "credits the whole order up front, tied to the first instalment and its subscription", context do
      %{account: account, stripe: stripe} = context
      params = instalment_order(context, %{"tuist_runner_prepaid_instalments" => "true"})

      assert {:ok, result} = RunnerBilling.activate(account.id, params, %{name: "atlas"})
      assert result.activation.status == "applied"

      assert [grant] = Agent.get(stripe, & &1.grants)
      # 12 × 1,227 at 1.25, regardless of how many instalments are paid.
      assert grant.amount.monetary == %{currency: "usd", value: 1_840_500}
      assert grant.metadata["tuist_prepaid_invoice_id"] == "in_instalment_1"
      assert grant.metadata["tuist_prepaid_instalments"] == "12"
      assert grant.metadata["tuist_prepaid_instalment_subscription_id"] == "sub_instalments"
      assert Repo.get_by!(PrepaidActivation, change_id: params["change_id"]).request["instalments"] == 12
    end

    test "refuses an invoice that is not one equal share of the order", context do
      %{account: account, stripe: stripe} = context
      params = instalment_order(context, %{"tuist_runner_prepaid_instalments" => "true"})

      assert {:error, :invoice_does_not_match} =
               RunnerBilling.activate(account.id, Map.put(params, "instalments", 11), %{})

      assert Agent.get(stripe, & &1.creates) == 0
    end

    test "refuses an instalment invoice from an unmarked or the runner subscription", context do
      %{account: account, stripe: stripe} = context
      params = instalment_order(context, %{})
      assert {:error, :instalment_subscription_required} = RunnerBilling.activate(account.id, params, %{})

      customer = Agent.get(stripe, & &1.subscription.customer)

      stub(Stripe.Invoice, :retrieve, fn _ ->
        {:ok, %{customer: customer, currency: "usd", subtotal: 122_700, status: "draft", subscription: "sub_prepaid"}}
      end)

      assert {:error, :instalment_subscription_required} = RunnerBilling.activate(account.id, params, %{})
      assert Agent.get(stripe, & &1.creates) == 0
      assert Trials.on_trial?(Repo.reload!(account))
    end

    test "rejects an instalment count outside 2..12", %{account: account, params: params} do
      for instalments <- [1, 13, "12"] do
        assert {:error, :invalid_request} =
                 RunnerBilling.activate(account.id, Map.put(params, "instalments", instalments), %{})
      end
    end
  end

  test "a top-up of a pool that covers cache covers cache with its Linux grant only", context do
    %{account: account, stripe: stripe, params: params} = context
    assert {:ok, _} = RunnerBilling.activate(account.id, Map.put(params, "covers_cache", true), %{})
    customer = Agent.get(stripe, & &1.subscription.customer)

    stub(Stripe.Invoice, :retrieve, fn "in_top_up" ->
      {:ok, %{customer: customer, currency: "usd", subtotal: 80_000, status: "open"}}
    end)

    assert {:ok, _} = RunnerBilling.top_up(account.id, top_up_request(account, %{}), %{})

    [_pool, macos, linux] = Agent.get(stripe, & &1.grants)
    assert macos.applicability_config.scope.prices == [%{id: "price_macos"}]
    refute Map.has_key?(macos.metadata, "tuist_prepaid_covers_cache")

    assert Enum.sort(linux.applicability_config.scope.prices) ==
             [%{id: "price_cache_egress"}, %{id: "price_cache_requests"}, %{id: "price_linux"}]

    assert linux.metadata["tuist_prepaid_covers_cache"] == "true"
    # At the Linux grant's own multiplier: 30,000 × 1.25.
    assert linux.amount.monetary == %{currency: "usd", value: 37_500}
  end

  describe "top_up/3" do
    setup %{account: account, params: params, stripe: stripe} do
      assert {:ok, _} = RunnerBilling.activate(account.id, params, %{})
      customer = Agent.get(stripe, & &1.subscription.customer)

      stub(Stripe.Invoice, :retrieve, fn
        "in_order" -> {:ok, %{customer: customer, currency: "usd", subtotal: 625_000, status: "paid"}}
        "in_top_up" -> {:ok, %{customer: customer, currency: "usd", subtotal: 80_000, status: "open"}}
      end)

      :ok
    end

    test "grants each platform at its own multiplier, expiring with the pool and spent first", context do
      %{account: account, stripe: stripe, params: pool} = context
      request = top_up_request(account, %{})

      assert {:ok, result} = RunnerBilling.top_up(account.id, request, %{name: "atlas"})
      assert length(result.prepaid_grants) == 3

      [pool_grant, macos, linux] = Agent.get(stripe, & &1.grants)
      assert macos.amount.monetary == %{currency: "usd", value: 59_215}
      assert macos.applicability_config.scope.prices == [%{id: "price_macos"}]
      assert linux.amount.monetary == %{currency: "usd", value: 37_500}
      assert linux.applicability_config.scope.prices == [%{id: "price_linux"}]

      for grant <- [macos, linux] do
        assert grant.expires_at == pool_grant.expires_at
        assert grant.priority < pool_grant.priority
        assert grant.metadata["tuist_prepaid_expires_on"] == pool["expires_on"]
        assert grant.metadata["tuist_prepaid_top_up_of"] == pool["change_id"]
        assert grant.metadata["tuist_prepaid_activation_id"] == request["change_id"]
        assert grant.metadata["tuist_prepaid_invoice_id"] == "in_top_up"
      end

      recorded = Repo.get_by!(PrepaidTopUp, change_id: request["change_id"])
      assert recorded.status == "applied"
      assert recorded.grant_ids == [macos.id, linux.id]
      assert recorded.principal == %{"name" => "atlas"}
      assert recorded.activation_id == Repo.get_by!(PrepaidActivation, change_id: pool["change_id"]).id

      # An identical replay returns the recorded result without Stripe.
      reject(&CreditGrants.list_for_customer/1)
      assert {:ok, replay} = RunnerBilling.top_up(account.id, request, %{name: "atlas"})
      assert replay == recorded.after
      assert {:error, :change_id_conflict} = RunnerBilling.top_up(account.id, Map.put(request, "reason", "x"), %{})
    end

    test "reconciles a grant whose response was lost without granting the platform twice", context do
      %{account: account, stripe: stripe} = context
      Agent.update(stripe, &%{&1 | ambiguous_grant: true})
      request = top_up_request(account, %{})

      assert {:error, :stripe_request_failed} = RunnerBilling.top_up(account.id, request, %{})
      assert Repo.get_by!(PrepaidTopUp, change_id: request["change_id"]).status == "pending"

      assert {:ok, _} = RunnerBilling.top_up(account.id, request, %{})
      # The pool plus one grant per platform.
      assert Agent.get(stripe, & &1.creates) == 3
      assert length(Repo.get_by!(PrepaidTopUp, change_id: request["change_id"]).grant_ids) == 2
    end

    test "refuses mismatched invoices, reused invoices, foreign platforms and reused change IDs", context do
      %{account: account, stripe: stripe, params: pool} = context

      assert {:error, :invoice_does_not_match} =
               RunnerBilling.top_up(
                 account.id,
                 top_up_request(account, %{
                   "grants" => [%{"platform" => "macos", "paid_cents" => 50_000, "credit_multiplier" => "1.1843"}]
                 }),
                 %{}
               )

      assert {:error, :invoice_already_used} =
               RunnerBilling.top_up(account.id, top_up_request(account, %{"invoice_id" => "in_order"}), %{})

      assert {:error, :change_id_conflict} =
               RunnerBilling.top_up(account.id, top_up_request(account, %{"change_id" => pool["change_id"]}), %{})

      Repo.update_all(PrepaidActivation, set: [request: Map.put(pool, "platforms", ["linux"])])

      assert {:error, :platform_not_in_pool} = RunnerBilling.top_up(account.id, top_up_request(account, %{}), %{})

      assert {:ok, _} =
               RunnerBilling.top_up(
                 account.id,
                 top_up_request(account, %{
                   "grants" => [%{"platform" => "linux", "paid_cents" => 80_000, "credit_multiplier" => "1.25"}]
                 }),
                 %{}
               )

      assert {:error, :invoice_already_used} =
               RunnerBilling.top_up(
                 account.id,
                 top_up_request(account, %{
                   "grants" => [%{"platform" => "linux", "paid_cents" => 80_000, "credit_multiplier" => "1.25"}]
                 }),
                 %{}
               )

      assert Agent.get(stripe, & &1.creates) == 2
    end

    test "refuses an account without a pool running past today", %{account: account, params: pool} do
      Repo.update_all(PrepaidActivation, set: [request: Map.put(pool, "expires_on", "2026-11-16")])
      assert {:error, :no_live_pool} = RunnerBilling.top_up(account.id, top_up_request(account, %{}), %{})
    end

    test "rejects malformed top-ups", %{account: account} do
      grant = %{"platform" => "macos", "paid_cents" => 80_000, "credit_multiplier" => "1.1843"}

      for override <- [
            %{"grants" => []},
            %{"grants" => [grant, grant]},
            %{"grants" => [Map.put(grant, "platform", "windows")]},
            %{"grants" => [Map.put(grant, "credit_multiplier", "1.18427")]},
            %{"grants" => [Map.put(grant, "credit_multiplier", "0.9")]},
            %{"grants" => [Map.put(grant, "extra", 1)]},
            %{"invoice_id" => "inv_x"},
            %{"interface" => "worker"},
            %{"extra" => 1}
          ] do
        assert {:error, :invalid_request} = RunnerBilling.top_up(account.id, top_up_request(account, override), %{})
      end
    end
  end

  defp instalment_order(%{params: params, stripe: stripe}, subscription_metadata) do
    customer = Agent.get(stripe, & &1.subscription.customer)

    stub(Stripe.Invoice, :retrieve, fn "in_instalment_1" ->
      {:ok, %{customer: customer, currency: "usd", subtotal: 122_700, status: "draft", subscription: "sub_instalments"}}
    end)

    stub(Stripe.Subscription, :retrieve, fn
      "sub_instalments" -> {:ok, %{id: "sub_instalments", customer: customer, metadata: subscription_metadata}}
      "sub_prepaid" -> {:ok, Agent.get(stripe, & &1.subscription)}
    end)

    Map.merge(params, %{
      "paid_cents" => 1_472_400,
      "credit_multiplier" => "1.25",
      "instalments" => 12,
      "invoice_id" => "in_instalment_1"
    })
  end

  defp top_up_request(account, attrs) do
    {:ok, state} = RunnerBilling.get(account.id)

    Map.merge(
      %{
        "grants" => [
          %{"platform" => "macos", "paid_cents" => 50_000, "credit_multiplier" => "1.1843"},
          %{"platform" => "linux", "paid_cents" => 30_000, "credit_multiplier" => "1.25"}
        ],
        "invoice_id" => "in_top_up",
        "expected_revision" => state.revision,
        "reason" => "Top-up order",
        "change_id" => Ecto.UUID.generate(),
        "actor" => %{"id" => Ecto.UUID.generate(), "email" => "operator@tuist.dev"},
        "interface" => "mcp"
      },
      attrs
    )
  end

  defp stripe_request(
         %{method: :get, endpoint: "/v1/billing/credit_grants"},
         %{fail_snapshot: true, schedule: %{metadata: metadata}} = state
       )
       when map_size(metadata) > 0, do: {{:error, :timeout}, %{state | fail_snapshot: false}}

  defp stripe_request(%{method: :get, endpoint: "/v1/billing/credit_grants"}, state),
    do: {{:ok, %{data: state.grants, has_more: false}}, state}

  defp stripe_request(%{method: :get, endpoint: "/v1/billing/credit_balance_summary"}, state),
    do: {{:ok, %{balances: [%{available_balance: %{monetary: %{value: 694_500}}}]}}, state}

  defp stripe_request(%{method: :post, endpoint: "/v1/billing/credit_grants", params: params}, state) do
    id = if state.creates == 0, do: "credgr_order", else: "credgr_order_#{state.creates}"
    grant = Map.put(params, :id, id)
    result = if state.ambiguous_grant, do: {:error, :timeout}, else: {:ok, grant}
    {result, %{state | grants: state.grants ++ [grant], creates: state.creates + 1, ambiguous_grant: false}}
  end

  defp stripe_request(%{method: :post, endpoint: "/v1/subscription_schedules"}, %{fail_schedule: true} = state),
    do: {{:error, %{code: "provider_unavailable"}}, state}

  defp stripe_request(%{method: :post, endpoint: "/v1/subscription_schedules"}, %{schedule: %{id: _}} = state),
    do: {{:ok, state.schedule}, state}

  defp stripe_request(%{method: :post, endpoint: "/v1/subscription_schedules"}, state) do
    phase = %{
      start_date: state.subscription.current_period_start,
      add_invoice_items: [%{price: "price_one_time"}],
      automatic_tax: %{enabled: false, disabled_reason: nil, liability: nil},
      items: Enum.map(state.subscription.items.data, fn item -> %{price: item.price.id, quantity: item.quantity} end)
    }

    schedule = %{id: "sub_sched_order", metadata: %{}, phases: [phase]}
    {{:ok, schedule}, %{state | schedule: schedule, subscription: %{state.subscription | schedule: schedule.id}}}
  end

  defp stripe_request(%{method: :get, endpoint: "/v1/subscription_schedules/sub_sched_order"}, state),
    do: {{:ok, state.schedule}, state}

  defp stripe_request(
         %{method: :post, endpoint: "/v1/subscription_schedules/sub_sched_order"},
         %{fail_update: true} = state
       ), do: {{:error, :timeout}, state}

  # Match Stripe's rejection of response-only nested tax fields.
  defp stripe_request(
         %{
           method: :post,
           endpoint: "/v1/subscription_schedules/sub_sched_order",
           params: %{phases: [%{automatic_tax: %{disabled_reason: _}} | _]}
         },
         state
       ), do: {{:error, :parameter_unknown}, state}

  defp stripe_request(%{method: :post, endpoint: "/v1/subscription_schedules/sub_sched_order", params: params}, state) do
    schedule = Map.merge(state.schedule, params)
    {{:ok, schedule}, %{state | schedule: schedule}}
  end
end
