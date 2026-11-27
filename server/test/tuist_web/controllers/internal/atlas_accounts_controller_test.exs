defmodule TuistWeb.Internal.AtlasAccountsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.AtlasWorkloadIdentity
  alias Tuist.Billing
  alias Tuist.Environment
  alias Tuist.Ops.AccountPlanChange
  alias Tuist.Ops.RunnerConcurrencyLimitChange
  alias Tuist.Ops.RunnerTrialChange
  alias Tuist.Repo
  alias Tuist.Runners.Concurrency
  alias Tuist.Runners.Trials
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures
  alias TuistWeb.RateLimit

  setup do
    stub(RateLimit.Atlas, :hit, fn _conn -> {:allow, 1} end)
    stub(AtlasWorkloadIdentity, :verify, fn "valid-token" -> {:ok, %{namespace: "atlas-production", name: "atlas"}} end)
    :ok
  end

  test "routes reject unauthenticated callers, including writes", %{conn: conn} do
    assert conn |> get("/api/internal/atlas/accounts/lookup", %{"handle" => "tuist"}) |> json_response(401)
    assert conn |> get("/api/internal/atlas/accounts/1/runner-concurrency-limits") |> json_response(401)
    assert conn |> put("/api/internal/atlas/accounts/1/runner-concurrency-limits", %{}) |> json_response(401)
    assert conn |> get("/api/internal/atlas/accounts/1/runner-billing") |> json_response(401)
    assert conn |> put("/api/internal/atlas/accounts/1/runner-billing", %{}) |> json_response(401)
    assert conn |> put("/api/internal/atlas/accounts/1/runner-trial", %{}) |> json_response(401)
  end

  test "runner billing reads use workload authentication and invalid activations do not mutate the account", %{conn: conn} do
    account = AccountsFixtures.organization_fixture(customer_id: nil, preload: [:account]).account
    path = "/api/internal/atlas/accounts/#{account.id}/runner-billing"

    assert %{"account_id" => id, "prepaid_grants" => [], "activation" => nil, "revision" => revision} =
             conn |> authed() |> get(path) |> json_response(200)

    assert id == account.id
    assert byte_size(revision) == 64
    assert %{"error" => "invalid_request"} = conn |> authed() |> put(path, %{}) |> json_response(422)
    assert Repo.reload!(account).runner_trial_ended_at == account.runner_trial_ended_at
  end

  test "lookup resolves an organization handle to its account ID, not the organization ID", %{conn: conn} do
    organization = AccountsFixtures.organization_fixture(name: "SteyCorp", preload: [:account])
    user = AccountsFixtures.user_fixture(preload: [:account])

    assert conn |> authed() |> get("/api/internal/atlas/accounts/lookup", %{"handle" => "steycorp"}) |> json_response(200) ==
             %{
               "account_id" => organization.account.id,
               "handle" => "SteyCorp",
               "type" => "organization",
               "organization_id" => organization.id,
               "user_id" => nil
             }

    assert %{"account_id" => account_id, "type" => "user", "user_id" => user_id} =
             conn
             |> authed()
             |> get("/api/internal/atlas/accounts/lookup", %{"handle" => user.account.name})
             |> json_response(200)

    assert account_id == user.account.id
    assert user_id == user.id

    assert %{"error" => "resource_not_found"} =
             conn
             |> authed()
             |> get("/api/internal/atlas/accounts/lookup", %{"handle" => "missing"})
             |> json_response(404)

    assert %{"error" => "invalid_request"} =
             conn |> authed() |> get("/api/internal/atlas/accounts/lookup") |> json_response(422)
  end

  test "reads limits with usage and defaults, and rejects unknown or malformed accounts", %{conn: conn} do
    account = AccountsFixtures.organization_fixture(preload: [:account]).account

    assert %{"account_id" => account_id, "account_handle" => handle, "revision" => revision, "limits" => limits} =
             conn |> authed() |> get(path(account.id)) |> json_response(200)

    assert account_id == account.id
    assert handle == account.name
    assert byte_size(revision) == 64

    assert limits == [
             %{
               "platform" => "linux",
               "vcpus" => 16,
               "memory_gb" => 64,
               "used_vcpus" => 0,
               "used_memory_gb" => 0,
               "default_vcpus" => 16,
               "default_memory_gb" => 64
             },
             %{
               "platform" => "macos",
               "vcpus" => 8,
               "memory_gb" => 24,
               "used_vcpus" => 0,
               "used_memory_gb" => 0,
               "default_vcpus" => 8,
               "default_memory_gb" => 24
             }
           ]

    assert %{"error" => "resource_not_found"} =
             conn |> authed() |> get(path(9_223_372_036_854_775_807)) |> json_response(404)

    for id <- ["0", "-1", "1.5", "9223372036854775808", "abc"] do
      assert %{"error" => "invalid_target"} = conn |> authed() |> get(path(id)) |> json_response(422)
    end
  end

  test "updates only the requested platform and audits the change atomically", %{conn: conn} do
    account = AccountsFixtures.organization_fixture(preload: [:account]).account
    other = AccountsFixtures.organization_fixture(preload: [:account]).account
    request = request(conn, account.id, %{"platform" => "macos", "vcpus" => 48, "memory_gb" => 144})

    result = conn |> authed() |> put(path(account.id), request) |> json_response(200)

    assert Enum.find(result["limits"], &(&1["platform"] == "macos"))["vcpus"] == 48
    assert Concurrency.limits_for(account, :macos) == %{vcpus: 48, memory_gb: 144}
    assert Concurrency.limits_for(account, :linux) == %{vcpus: 16, memory_gb: 64}
    assert Concurrency.limits_for(other, :macos) == %{vcpus: 8, memory_gb: 24}
    refute result["revision"] == request["expected_revision"]

    audit = Repo.get_by!(RunnerConcurrencyLimitChange, change_id: request["change_id"])
    assert audit.account_id == account.id
    assert audit.principal == %{"namespace" => "atlas-production", "name" => "atlas"}
    assert audit.request == request
    assert audit.before["revision"] == request["expected_revision"]
    assert Enum.find(audit.before["limits"], &(&1["platform"] == "macos"))["vcpus"] == 8
    assert audit.after == result
  end

  test "retries are idempotent and stale revisions or reused change IDs cannot overwrite a later change", %{conn: conn} do
    account = AccountsFixtures.organization_fixture(preload: [:account]).account
    request = request(conn, account.id, %{"platform" => "linux", "vcpus" => 64, "memory_gb" => 128})
    first = conn |> authed() |> put(path(account.id), request) |> json_response(200)

    later = request(conn, account.id, %{"platform" => "linux", "vcpus" => 40, "memory_gb" => 80})
    conn |> authed() |> put(path(account.id), later) |> json_response(200)

    # The original request replays its recorded result without reapplying it.
    assert conn |> authed() |> put(path(account.id), request) |> json_response(200) == first
    assert Concurrency.limits_for(account, :linux) == %{vcpus: 40, memory_gb: 80}

    stale = Map.put(request, "change_id", Ecto.UUID.generate())

    assert %{"error" => "stale_revision"} =
             conn |> authed() |> put(path(account.id), stale) |> json_response(409)

    reused = Map.put(request, "reason", "Different request")

    assert %{"error" => "change_id_conflict"} =
             conn |> authed() |> put(path(account.id), reused) |> json_response(409)

    other = AccountsFixtures.organization_fixture(preload: [:account]).account
    elsewhere = request(conn, other.id, Map.take(request, ~w(platform vcpus memory_gb change_id)))

    assert %{"error" => "change_id_conflict"} =
             conn |> authed() |> put(path(other.id), elsewhere) |> json_response(409)

    assert Concurrency.limits_for(account, :linux) == %{vcpus: 40, memory_gb: 80}
    assert Concurrency.limits_for(other, :linux) == %{vcpus: 16, memory_gb: 64}
    assert Repo.aggregate(RunnerConcurrencyLimitChange, :count) == 2
  end

  test "ops dashboard edits invalidate the revision Atlas read, even when they restore the same values", %{conn: conn} do
    account = AccountsFixtures.organization_fixture(preload: [:account]).account

    # Back-date the rows so the dashboard writes land in a later second.
    Repo.update_all(Ecto.assoc(account, :runner_concurrency_limits), set: [updated_at: ~U[2026-01-01 00:00:00Z]])
    request = request(conn, account.id, %{"platform" => "macos", "vcpus" => 32, "memory_gb" => 96})

    for {vcpus, memory_gb} <- [{24, 72}, {16, 48}] do
      {:ok, _} =
        Concurrency.update_limits(account, %{
          runner_linux_vcpus_limit: 32,
          runner_linux_memory_gb_limit: 64,
          runner_macos_vcpus_limit: vcpus,
          runner_macos_memory_gb_limit: memory_gb
        })
    end

    assert %{"error" => "stale_revision"} =
             conn |> authed() |> put(path(account.id), request) |> json_response(409)

    assert Concurrency.limits_for(account, :macos) == %{vcpus: 16, memory_gb: 48}
  end

  test "invalid limits and forged or unknown fields never change limits", %{conn: conn} do
    account = AccountsFixtures.organization_fixture(preload: [:account]).account

    for attrs <- [
          %{"platform" => "windows"},
          %{"vcpus" => 0},
          %{"memory_gb" => -1},
          %{"vcpus" => "32"},
          %{"vcpus" => 1.5},
          %{"vcpus" => 2_147_483_648},
          %{"reason" => " "},
          %{"change_id" => "not-a-uuid"},
          %{"expected_revision" => "short"},
          %{"actor" => %{"id" => "forged", "email" => "test@example.com"}},
          %{"interface" => "slack"},
          %{"account_id" => account.id}
        ] do
      params = request(conn, account.id, Map.merge(%{"platform" => "macos", "vcpus" => 32, "memory_gb" => 96}, attrs))

      assert %{"error" => "invalid_request"} =
               conn |> authed() |> put(path(account.id), params) |> json_response(422)
    end

    params = request(conn, account.id, %{"platform" => "macos", "vcpus" => 32})
    assert conn |> authed() |> put(path(account.id), params) |> json_response(422)

    assert Concurrency.limits_for(account, :macos) == %{vcpus: 8, memory_gb: 24}
    assert Repo.aggregate(RunnerConcurrencyLimitChange, :count) == 0
  end

  describe "plan" do
    setup do
      stub(Environment, :stripe_prices, fn ->
        %{
          "air" => %{"usage" => ["air.usage"], "flat_monthly" => ["air.flat.monthly"]},
          "enterprise" => %{"usage" => ["enterprise.usage"], "flat_monthly" => ["enterprise.flat.monthly"]},
          "open_source" => %{"usage" => ["open_source.usage"], "flat_monthly" => ["open_source.flat.monthly"]},
          "runners" => %{}
        }
      end)

      :ok
    end

    test "an account whose Enterprise subscription ended reads as Air, with the ended subscription listed", %{conn: conn} do
      account = AccountsFixtures.organization_fixture(preload: [:account]).account

      BillingFixtures.subscription_fixture(
        account_id: account.id,
        subscription_id: "sub_old_enterprise",
        plan: :enterprise,
        status: "canceled"
      )

      assert %{
               "account_id" => account_id,
               "account_handle" => handle,
               "stripe_customer_id" => customer_id,
               "effective_plan" => "air",
               "subscription" => nil,
               "recent_subscriptions" => [
                 %{"subscription_id" => "sub_old_enterprise", "plan" => "enterprise", "status" => "canceled"}
               ],
               "payment_failed" => false,
               "cache_access_blocked" => false,
               "revision" => revision
             } = conn |> authed() |> get(plan_path(account.id)) |> json_response(200)

      assert {account_id, handle, customer_id} == {account.id, account.name, account.customer_id}
      assert byte_size(revision) == 64

      assert %{"error" => "resource_not_found"} =
               conn |> authed() |> get(plan_path(9_223_372_036_854_775_807)) |> json_response(404)

      assert conn |> get(plan_path(account.id)) |> json_response(401)
      assert conn |> put(plan_path(account.id), %{}) |> json_response(401)
    end

    test "upgrades to Enterprise with the billing details Stripe has, records the change once and replays it", %{
      conn: conn
    } do
      account = AccountsFixtures.organization_fixture(customer_id: "cus_acme", preload: [:account]).account
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise, status: "canceled")
      request = plan_request(conn, account.id, %{"operation" => "upgrade_to_enterprise"})

      stub(Stripe.Customer, :retrieve, fn "cus_acme" -> {:ok, complete_customer()} end)
      reject(&Stripe.Customer.update/2)

      expect(Stripe.Subscription, :create, 1, fn %{
                                                   customer: "cus_acme",
                                                   collection_method: "send_invoice",
                                                   items: [
                                                     %{price: "enterprise.usage"},
                                                     %{price: "enterprise.flat.monthly", quantity: 0}
                                                   ]
                                                 } ->
        {:ok, stripe_subscription("sub_enterprise", "cus_acme", "enterprise.flat.monthly")}
      end)

      result = conn |> authed() |> put(plan_path(account.id), request) |> json_response(200)

      assert %{"effective_plan" => "enterprise", "subscription" => %{"subscription_id" => "sub_enterprise"}} = result
      refute result["revision"] == request["expected_revision"]

      change = Repo.get_by!(AccountPlanChange, change_id: request["change_id"])
      assert change.account_id == account.id
      assert change.request == request
      assert change.principal == %{"namespace" => "atlas-production", "name" => "atlas"}
      assert change.before["effective_plan"] == "air"
      assert change.after == result

      # A retry after an ambiguous outcome returns the recorded result without
      # calling Stripe again (the expectation above allows one call).
      assert conn |> authed() |> put(plan_path(account.id), request) |> json_response(200) == result

      # A new decision based on the old revision is refused.
      stale = Map.put(request, "change_id", Ecto.UUID.generate())
      assert %{"error" => "stale_revision"} = conn |> authed() |> put(plan_path(account.id), stale) |> json_response(409)

      fresh = plan_request(conn, account.id, %{"operation" => "upgrade_to_enterprise"})

      assert %{"error" => "already_enterprise"} =
               conn |> authed() |> put(plan_path(account.id), fresh) |> json_response(409)

      assert Repo.aggregate(AccountPlanChange, :count) == 1
    end

    test "Enterprise upgrades need billing details when Stripe lacks them", %{conn: conn} do
      account = AccountsFixtures.organization_fixture(customer_id: "cus_new", preload: [:account]).account
      stub(Stripe.Customer, :retrieve, fn "cus_new" -> {:ok, %Stripe.Customer{id: "cus_new", name: "New"}} end)

      # Expected once, below: the refused request must not create a subscription.
      expect(Stripe.Subscription, :create, 1, fn %{customer: "cus_new"} ->
        {:ok, stripe_subscription("sub_new", "cus_new", "enterprise.flat.monthly")}
      end)

      request = plan_request(conn, account.id, %{"operation" => "upgrade_to_enterprise"})

      assert %{"error" => "billing_details_required"} =
               conn |> authed() |> put(plan_path(account.id), request) |> json_response(422)

      assert Repo.aggregate(AccountPlanChange, :count) == 0
      assert Billing.effective_plan(account) == :air

      expect(Stripe.Customer, :update, fn "cus_new",
                                          %{
                                            name: "New Corp",
                                            email: "billing@new.test",
                                            address: %{
                                              line1: "1 Main St",
                                              city: "Berlin",
                                              postal_code: "10115",
                                              country: "DE"
                                            }
                                          } ->
        {:ok, %Stripe.Customer{id: "cus_new"}}
      end)

      with_details =
        Map.merge(request, %{
          "change_id" => Ecto.UUID.generate(),
          "billing_details" => %{
            "name" => "New Corp",
            "email" => "billing@new.test",
            "address" => %{"line1" => "1 Main St", "city" => "Berlin", "postal_code" => "10115", "country" => "de"}
          }
        })

      assert %{"effective_plan" => "enterprise"} =
               conn |> authed() |> put(plan_path(account.id), with_details) |> json_response(200)
    end

    test "starts the open source plan only without a live subscription", %{conn: conn} do
      account = AccountsFixtures.organization_fixture(customer_id: "cus_oss", preload: [:account]).account

      expect(Stripe.Subscription, :create, fn %{customer: "cus_oss"} ->
        {:ok, stripe_subscription("sub_oss", "cus_oss", ["open_source.flat.monthly", "open_source.usage"])}
      end)

      request = plan_request(conn, account.id, %{"operation" => "start_open_source"})

      assert %{"effective_plan" => "open_source"} =
               conn |> authed() |> put(plan_path(account.id), request) |> json_response(200)

      again = plan_request(conn, account.id, %{"operation" => "start_open_source"})

      assert %{"error" => "subscription_exists"} =
               conn |> authed() |> put(plan_path(account.id), again) |> json_response(409)

      assert Repo.aggregate(AccountPlanChange, :count) == 1
    end

    test "cancels the live subscription at period end, once", %{conn: conn} do
      account = AccountsFixtures.organization_fixture(customer_id: "cus_cancel", preload: [:account]).account
      BillingFixtures.subscription_fixture(account_id: account.id, subscription_id: "sub_live", plan: :enterprise)

      expect(Stripe.Subscription, :update, fn "sub_live", %{cancel_at_period_end: true} ->
        {:ok,
         Map.put(stripe_subscription("sub_live", "cus_cancel", "enterprise.flat.monthly"), :cancel_at_period_end, true)}
      end)

      request = plan_request(conn, account.id, %{"operation" => "cancel_at_period_end"})

      # Access is kept until the period ends.
      assert %{"effective_plan" => "enterprise", "subscription" => %{"cancel_at_period_end" => true}} =
               conn |> authed() |> put(plan_path(account.id), request) |> json_response(200)

      again = plan_request(conn, account.id, %{"operation" => "cancel_at_period_end"})

      assert %{"error" => "no_cancellable_subscription"} =
               conn |> authed() |> put(plan_path(account.id), again) |> json_response(409)
    end

    test "schedules an Enterprise subscription's switch to Pro once the customer has a card", %{conn: conn} do
      stub(Environment, :stripe_prices, fn ->
        %{
          "enterprise" => %{"usage" => ["enterprise.usage"], "flat_monthly" => ["enterprise.flat.monthly"]},
          "pro" => %{"usage" => ["pro.usage"], "flat_monthly" => ["pro.flat.monthly"]},
          "usage_meters" => %{
            "cache_egress_megabytes" => "pro.egress",
            "cache_requests" => "pro.requests",
            "passing_test_cases" => "pro.tests"
          },
          "runners" => %{"runner_minutes" => "runner.minutes"}
        }
      end)

      account = AccountsFixtures.organization_fixture(customer_id: "cus_nell", preload: [:account]).account
      BillingFixtures.subscription_fixture(account_id: account.id, subscription_id: "sub_free", plan: :enterprise)
      starts_at = DateTime.utc_now() |> DateTime.add(10, :day) |> DateTime.truncate(:second)
      attrs = %{"operation" => "schedule_pro", "starts_at" => DateTime.to_iso8601(starts_at)}

      # Without a card the first Pro invoice could not be charged.
      stub(Stripe.Customer, :retrieve, fn "cus_nell" ->
        {:ok, %Stripe.Customer{id: "cus_nell", invoice_settings: %{default_payment_method: nil}}}
      end)

      stub(Stripe.SubscriptionSchedule, :create, fn _params -> flunk("scheduled without a payment method") end)

      assert %{"error" => "payment_method_required"} =
               conn |> authed() |> put(plan_path(account.id), plan_request(conn, account.id, attrs)) |> json_response(422)

      stub(Stripe.Customer, :retrieve, fn "cus_nell" ->
        {:ok, %Stripe.Customer{id: "cus_nell", invoice_settings: %{default_payment_method: "pm_card"}}}
      end)

      expect(Stripe.SubscriptionSchedule, :create, fn %{from_subscription: "sub_free"} ->
        {:ok,
         %{
           id: "sub_sched",
           phases: [%{start_date: 1_790_000_000, items: [%{price: "enterprise.flat.monthly", quantity: 0}]}]
         }}
      end)

      starts_at_unix = DateTime.to_unix(starts_at)

      expect(Stripe.SubscriptionSchedule, :update, fn "sub_sched", %{end_behavior: "release", phases: phases} ->
        assert [
                 %{
                   items: [%{price: "enterprise.flat.monthly", quantity: 0}],
                   start_date: 1_790_000_000,
                   end_date: ^starts_at_unix
                 },
                 %{
                   items: [
                     %{price: "pro.egress"},
                     %{price: "pro.requests"},
                     %{price: "pro.tests"},
                     %{price: "runner.minutes"},
                     %{price: "pro.flat.monthly", quantity: 1}
                   ],
                   billing_cycle_anchor: "phase_start",
                   proration_behavior: "none",
                   collection_method: "charge_automatically"
                 }
               ] = phases

        {:ok, %{id: "sub_sched"}}
      end)

      request = plan_request(conn, account.id, attrs)

      # The account stays on Enterprise until the schedule switches it.
      assert %{"effective_plan" => "enterprise"} =
               conn |> authed() |> put(plan_path(account.id), request) |> json_response(200)

      assert Repo.get_by!(AccountPlanChange, change_id: request["change_id"]).request["starts_at"] ==
               attrs["starts_at"]

      # When Stripe refuses the phases, the new schedule is released and nothing is recorded.
      expect(Stripe.SubscriptionSchedule, :create, fn _ ->
        {:ok, %{id: "sub_sched_2", phases: [%{start_date: 1, items: []}]}}
      end)

      expect(Stripe.SubscriptionSchedule, :update, fn "sub_sched_2", _ ->
        {:error, %Stripe.Error{source: :stripe, code: :invalid_request_error, message: "no"}}
      end)

      expect(Stripe.SubscriptionSchedule, :release, fn "sub_sched_2" -> {:ok, %{id: "sub_sched_2"}} end)

      assert %{"error" => "stripe_request_failed"} =
               conn |> authed() |> put(plan_path(account.id), plan_request(conn, account.id, attrs)) |> json_response(502)

      assert Repo.aggregate(AccountPlanChange, :count) == 1
    end

    test "switches a $0 EUR Enterprise subscription to USD with the runner prices, restoring it when Stripe refuses",
         %{conn: conn} do
      stub(Environment, :stripe_prices, fn ->
        %{
          "enterprise" => %{"usage" => [], "flat_monthly" => ["enterprise.flat.eur", "enterprise.flat.usd"]},
          "runners" => %{"runner_minutes" => "runner.minutes.usd"}
        }
      end)

      stub(Stripe.Price, :retrieve, fn id -> {:ok, %{id: id, currency: id |> String.split(".") |> List.last()}} end)
      stub(Stripe.Invoice, :list, fn %{customer: "cus_eur", status: "open"} -> {:ok, %{data: []}} end)

      account = AccountsFixtures.organization_fixture(customer_id: "cus_eur", preload: [:account]).account
      BillingFixtures.subscription_fixture(account_id: account.id, subscription_id: "sub_eur", plan: :enterprise)

      eur_subscription = fn quantity ->
        %{
          id: "sub_eur",
          customer: "cus_eur",
          currency: "eur",
          collection_method: "send_invoice",
          days_until_due: 14,
          current_period_end: 1_800_000_000,
          items: %{
            data: [
              %{
                price: %{id: "enterprise.flat.eur", recurring: %{usage_type: "licensed"}},
                quantity: quantity
              }
            ]
          }
        }
      end

      # A subscription that bills seats is left alone: cancelling it would drop what it bills.
      stub(Stripe.Subscription, :retrieve, fn "sub_eur" -> {:ok, eur_subscription.(3)} end)

      assert %{"error" => "billable_subscription"} =
               conn
               |> authed()
               |> put(plan_path(account.id), plan_request(conn, account.id, %{"operation" => "switch_to_usd"}))
               |> json_response(409)

      stub(Stripe.Subscription, :retrieve, fn "sub_eur" -> {:ok, eur_subscription.(0)} end)

      cancelled = Map.put(stripe_subscription("sub_eur", "cus_eur", "enterprise.flat.eur"), :status, "canceled")
      expect(Stripe.Subscription, :cancel, 2, fn "sub_eur", %{invoice_now: false, prorate: false} -> {:ok, cancelled} end)

      expect(Stripe.Subscription, :create, fn params ->
        assert %{
                 customer: "cus_eur",
                 items: [%{price: "runner.minutes.usd"}, %{price: "enterprise.flat.usd", quantity: 0}],
                 collection_method: "send_invoice",
                 days_until_due: 14,
                 billing_cycle_anchor: 1_800_000_000,
                 proration_behavior: "none"
               } = params

        {:ok, stripe_subscription("sub_usd", "cus_eur", ["runner.minutes.usd", "enterprise.flat.usd"])}
      end)

      assert %{"effective_plan" => "enterprise", "subscription" => %{"subscription_id" => "sub_usd"}} =
               conn
               |> authed()
               |> put(plan_path(account.id), plan_request(conn, account.id, %{"operation" => "switch_to_usd"}))
               |> json_response(200)

      # When Stripe refuses the USD subscription, the EUR one is recreated so the account keeps Enterprise.
      Repo.delete_all(Tuist.Billing.Subscription)
      BillingFixtures.subscription_fixture(account_id: account.id, subscription_id: "sub_eur", plan: :enterprise)

      expect(Stripe.Subscription, :create, 2, fn
        %{items: [%{price: "runner.minutes.usd"} | _]} ->
          {:error, %Stripe.Error{source: :stripe, code: :invalid_request_error, message: "no"}}

        %{items: [%{price: "enterprise.flat.eur", quantity: 0}]} ->
          {:ok, stripe_subscription("sub_eur_2", "cus_eur", "enterprise.flat.eur")}
      end)

      assert %{"error" => "stripe_request_failed"} =
               conn
               |> authed()
               |> put(plan_path(account.id), plan_request(conn, account.id, %{"operation" => "switch_to_usd"}))
               |> json_response(502)

      assert Billing.effective_plan(account) == :enterprise
    end

    test "a subscription webhook invalidates the revision Atlas read", %{conn: conn} do
      account = AccountsFixtures.organization_fixture(customer_id: "cus_hook", preload: [:account]).account
      request = plan_request(conn, account.id, %{"operation" => "start_open_source"})
      reject(&Stripe.Subscription.create/1)

      :ok = Billing.on_subscription_change(stripe_subscription("sub_ops", "cus_hook", "enterprise.flat.monthly"))

      assert %{"error" => "stale_revision"} =
               conn |> authed() |> put(plan_path(account.id), request) |> json_response(409)
    end

    test "malformed or forged requests never reach Stripe", %{conn: conn} do
      account = AccountsFixtures.organization_fixture(preload: [:account]).account
      reject(&Stripe.Subscription.create/1)
      reject(&Stripe.Customer.retrieve/1)

      details = %{
        "name" => "Acme",
        "email" => "billing@acme.test",
        "address" => %{"line1" => "1 Market St", "city" => "SF", "postal_code" => "94105", "country" => "US"}
      }

      for attrs <- [
            %{"operation" => "upgrade_to_pro"},
            %{"starts_at" => "2099-01-01T00:00:00Z"},
            %{"operation" => "schedule_pro"},
            %{"operation" => "schedule_pro", "starts_at" => "2020-01-01T00:00:00Z"},
            %{"operation" => "schedule_pro", "starts_at" => "2099-01-01T00:00:00Z"},
            %{"operation" => "start_open_source", "billing_details" => details},
            %{"billing_details" => put_in(details, ["address", "country"], "USA")},
            %{"billing_details" => Map.delete(details, "email")},
            %{"billing_details" => put_in(details, ["address", "unit"], "4")},
            %{"billing_details" => Map.put(details, "address", %{"line1" => "1 Market St"})},
            %{"reason" => " "},
            %{"interface" => "slack"},
            %{"actor" => %{"id" => "forged", "email" => "operator@example.com"}},
            %{"plan" => "enterprise"}
          ] do
        params = plan_request(conn, account.id, Map.merge(%{"operation" => "upgrade_to_enterprise"}, attrs))

        assert %{"error" => "invalid_request"} =
                 conn |> authed() |> put(plan_path(account.id), params) |> json_response(422)
      end

      assert Repo.aggregate(AccountPlanChange, :count) == 0
    end
  end

  describe "runner trial" do
    test "starts a trial, records the change once, replays it and refuses to restart it", %{conn: conn} do
      account = AccountsFixtures.organization_fixture(customer_id: nil, preload: [:account]).account
      request = trial_request(conn, account.id, %{"operation" => "start"})

      expect(Billing, :sync_runner_subscription_items, fn synced ->
        assert Trials.on_trial?(synced)
        {:ok, :no_subscription}
      end)

      result = conn |> authed() |> put(trial_path(account.id), request) |> json_response(200)

      assert %{"runner_trial" => %{"active" => true, "started_at" => started_at, "ended_at" => nil}} = result
      assert started_at
      refute result["revision"] == request["expected_revision"]
      # The returned state is what the next read sees, so its revision is current.
      assert result ==
               conn |> authed() |> get("/api/internal/atlas/accounts/#{account.id}/runner-billing") |> json_response(200)

      change = Repo.get_by!(RunnerTrialChange, change_id: request["change_id"])
      assert {change.account_id, change.request} == {account.id, request}
      assert change.principal == %{"namespace" => "atlas-production", "name" => "atlas"}
      assert change.before["runner_trial"]["active"] == false
      assert change.after == result

      # An identical retry replays without touching Stripe; reusing the ID for another request conflicts.
      assert ^result = conn |> authed() |> put(trial_path(account.id), request) |> json_response(200)

      assert %{"error" => "change_id_conflict"} =
               conn
               |> authed()
               |> put(trial_path(account.id), %{request | "reason" => "Something else"})
               |> json_response(409)

      again = trial_request(conn, account.id, %{"operation" => "start"})

      assert %{"error" => "already_on_trial"} =
               conn |> authed() |> put(trial_path(account.id), again) |> json_response(409)

      assert Repo.aggregate(RunnerTrialChange, :count) == 1
    end

    test "cancelling an Air account's trial needs confirm_air_limits", %{conn: conn} do
      account = trial_account()
      request = trial_request(conn, account.id, %{"operation" => "cancel"})
      stub(Billing, :sync_runner_subscription_items, fn _ -> {:ok, :no_subscription} end)

      assert %{"error" => "paid_plan_required"} =
               conn |> authed() |> put(trial_path(account.id), request) |> json_response(409)

      assert Trials.on_trial?(Repo.reload!(account))
      assert Repo.aggregate(RunnerTrialChange, :count) == 0

      confirmed = Map.put(request, "confirm_air_limits", true)

      assert %{"runner_trial" => %{"active" => false, "ended_at" => ended_at}} =
               conn |> authed() |> put(trial_path(account.id), confirmed) |> json_response(200)

      assert ended_at

      again = trial_request(conn, account.id, %{"operation" => "cancel", "confirm_air_limits" => true})

      assert %{"error" => "not_on_trial"} =
               conn |> authed() |> put(trial_path(account.id), again) |> json_response(409)
    end

    test "cancels a paid account's trial, and a Stripe failure leaves the trial and audit untouched", %{conn: conn} do
      account = trial_account()
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro)
      request = trial_request(conn, account.id, %{"operation" => "cancel"})

      expect(Billing, :sync_runner_subscription_items, fn synced ->
        refute Trials.on_trial?(synced)
        {:error, %Stripe.Error{source: :stripe, code: :api_error, message: "down"}}
      end)

      assert %{"error" => "stripe_request_failed"} =
               conn |> authed() |> put(trial_path(account.id), request) |> json_response(502)

      assert Trials.on_trial?(Repo.reload!(account))
      assert Repo.aggregate(RunnerTrialChange, :count) == 0

      expect(Billing, :sync_runner_subscription_items, fn _ -> {:ok, :updated} end)

      assert %{"runner_trial" => %{"active" => false}} =
               conn |> authed() |> put(trial_path(account.id), request) |> json_response(200)

      assert Repo.aggregate(RunnerTrialChange, :count) == 1
    end

    test "adds the runner items a paid subscription lacks, from now, and records the change once", %{conn: conn} do
      account = AccountsFixtures.organization_fixture(customer_id: nil, preload: [:account]).account
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro)
      request = trial_request(conn, account.id, %{"operation" => "add_runner_items"})
      before = DateTime.utc_now(:second)

      expect(Billing, :sync_runner_subscription_items, fn synced ->
        # The end is stamped before Stripe is reached, so the day splits at the moment the items appear.
        refute Trials.on_trial?(synced)
        assert synced.runner_trial_ended_at
        {:ok, %Stripe.Subscription{id: "sub_live"}}
      end)

      assert %{"runner_trial" => %{"active" => false, "started_at" => nil, "ended_at" => ended_at}} =
               result = conn |> authed() |> put(trial_path(account.id), request) |> json_response(200)

      {:ok, ended_at, 0} = DateTime.from_iso8601(ended_at)
      refute DateTime.before?(ended_at, before)

      change = Repo.get_by!(RunnerTrialChange, change_id: request["change_id"])
      assert change.after == result
      assert ^result = conn |> authed() |> put(trial_path(account.id), request) |> json_response(200)
      assert Repo.aggregate(RunnerTrialChange, :count) == 1
    end

    test "add_runner_items changes nothing when there is nothing to add, on Air, or on a trial", %{conn: conn} do
      paid = AccountsFixtures.organization_fixture(customer_id: nil, preload: [:account]).account
      BillingFixtures.subscription_fixture(account_id: paid.id, plan: :enterprise)
      expect(Billing, :sync_runner_subscription_items, fn _ -> {:ok, :unchanged} end)

      assert %{"error" => "runner_items_present"} =
               conn
               |> authed()
               |> put(trial_path(paid.id), trial_request(conn, paid.id, %{"operation" => "add_runner_items"}))
               |> json_response(409)

      assert is_nil(Repo.reload!(paid).runner_trial_ended_at)

      reject(&Billing.sync_runner_subscription_items/1)
      air = AccountsFixtures.organization_fixture(customer_id: nil, preload: [:account]).account

      assert %{"error" => "paid_plan_required"} =
               conn
               |> authed()
               |> put(trial_path(air.id), trial_request(conn, air.id, %{"operation" => "add_runner_items"}))
               |> json_response(409)

      on_trial = trial_account()
      BillingFixtures.subscription_fixture(account_id: on_trial.id, plan: :pro)

      assert %{"error" => "on_trial"} =
               conn
               |> authed()
               |> put(trial_path(on_trial.id), trial_request(conn, on_trial.id, %{"operation" => "add_runner_items"}))
               |> json_response(409)

      assert Trials.on_trial?(Repo.reload!(on_trial))
      assert Repo.aggregate(RunnerTrialChange, :count) == 0
    end

    test "malformed or forged requests never change the trial", %{conn: conn} do
      account = trial_account()
      reject(&Billing.sync_runner_subscription_items/1)

      for attrs <- [
            %{"operation" => "restart"},
            %{"operation" => "start", "confirm_air_limits" => true},
            %{"confirm_air_limits" => "yes"},
            %{"reason" => " "},
            %{"interface" => "slack"},
            %{"actor" => %{"id" => "forged", "email" => "operator@example.com"}},
            %{"ended_at" => "2026-01-01T00:00:00Z"}
          ] do
        params = trial_request(conn, account.id, Map.merge(%{"operation" => "cancel"}, attrs))

        assert %{"error" => "invalid_request"} =
                 conn |> authed() |> put(trial_path(account.id), params) |> json_response(422)
      end

      stale =
        conn
        |> trial_request(account.id, %{"operation" => "cancel"})
        |> Map.put("expected_revision", String.duplicate("0", 64))

      assert %{"error" => "stale_revision"} =
               conn |> authed() |> put(trial_path(account.id), stale) |> json_response(409)

      assert Trials.on_trial?(Repo.reload!(account))
      assert Repo.aggregate(RunnerTrialChange, :count) == 0
    end
  end

  defp trial_account do
    account = AccountsFixtures.organization_fixture(customer_id: nil, preload: [:account]).account

    account
    |> Ecto.Changeset.change(runner_trial_started_at: DateTime.add(DateTime.utc_now(:second), -1, :day))
    |> Repo.update!()
  end

  defp trial_path(account_id), do: "/api/internal/atlas/accounts/#{account_id}/runner-trial"

  defp trial_request(conn, account_id, attrs) do
    path = "/api/internal/atlas/accounts/#{account_id}/runner-billing"
    %{"revision" => revision} = conn |> authed() |> get(path) |> json_response(200)

    Map.merge(
      %{
        "expected_revision" => revision,
        "reason" => "Bringing the account onto runners",
        "change_id" => Ecto.UUID.generate(),
        "actor" => %{"id" => "273ee746-33fb-4db0-bc1d-7c3b6a602e6d", "email" => "operator@example.com"},
        "interface" => "mcp"
      },
      attrs
    )
  end

  defp plan_path(account_id), do: "/api/internal/atlas/accounts/#{account_id}/plan"

  defp plan_request(conn, account_id, attrs) do
    %{"revision" => revision} = conn |> authed() |> get(plan_path(account_id)) |> json_response(200)

    Map.merge(
      %{
        "expected_revision" => revision,
        "reason" => "Enterprise contract signed",
        "change_id" => Ecto.UUID.generate(),
        "actor" => %{"id" => "273ee746-33fb-4db0-bc1d-7c3b6a602e6d", "email" => "operator@example.com"},
        "interface" => "mcp"
      },
      attrs
    )
  end

  defp complete_customer do
    %Stripe.Customer{
      id: "cus_acme",
      name: "Acme",
      email: "ap@acme.test",
      address: %{line1: "1 Example Street", city: "Springfield", postal_code: "12345", country: "US"}
    }
  end

  defp stripe_subscription(id, customer, price_ids) do
    %{
      id: id,
      status: "active",
      customer: customer,
      default_payment_method: nil,
      cancel_at_period_end: false,
      items: %{data: Enum.map(List.wrap(price_ids), &%{price: %{id: &1}})}
    }
  end

  defp authed(conn), do: put_req_header(conn, "authorization", "Bearer valid-token")

  defp path(account_id), do: "/api/internal/atlas/accounts/#{account_id}/runner-concurrency-limits"

  defp request(conn, account_id, attrs) do
    %{"revision" => revision} = conn |> authed() |> get(path(account_id)) |> json_response(200)

    Map.merge(
      %{
        "expected_revision" => revision,
        "reason" => "Customer onboarding to runners",
        "change_id" => Ecto.UUID.generate(),
        "actor" => %{"id" => "273ee746-33fb-4db0-bc1d-7c3b6a602e6d", "email" => "operator@example.com"},
        "interface" => "mcp"
      },
      attrs
    )
  end
end
