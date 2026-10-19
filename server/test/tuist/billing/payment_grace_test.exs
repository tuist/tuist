defmodule Tuist.Billing.PaymentGraceTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Ecto.Adapters.SQL.Sandbox
  alias Stripe.Checkout.Session
  alias Tuist.Billing
  alias Tuist.Billing.AirUsageNotifications
  alias Tuist.Billing.Subscription
  alias Tuist.Billing.UsagePricing
  alias Tuist.Billing.Workers.AirUsageNotificationWorker
  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias Tuist.Repo
  alias Tuist.Storage.RetentionPolicy
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  @now ~U[2026-10-16 12:00:00Z]
  @cutoff ~U[2026-10-09 12:00:00Z]

  setup do
    stub(DateTime, :utc_now, fn -> @now end)
    stub(FeatureFlags, :usage_based_pricing_enabled?, fn _account -> false end)

    stub(Environment, :stripe_prices, fn ->
      %{
        "air" => %{"usage" => ["air.usage"], "flat_monthly" => ["air.flat"]},
        "pro" => %{"usage" => ["pro.usage"], "flat_monthly" => ["pro.flat"]},
        "runners" => %{}
      }
    end)

    :ok
  end

  test "SQL and preloaded plans agree immediately before, at, and after the grace deadline" do
    for {since, entitled?} <- [{DateTime.add(@cutoff, 1), true}, {@cutoff, false}, {DateTime.add(@cutoff, -1), false}] do
      account = AccountsFixtures.user_fixture(preload: [:account]).account

      subscription =
        BillingFixtures.subscription_fixture(account_id: account.id, status: "past_due", past_due_since: since)

      expected_plan = if entitled?, do: :pro, else: :air
      assert Subscription.entitled?(subscription) == entitled?
      assert Billing.effective_plan(account) == expected_plan
      assert Billing.effective_plan(%{account | subscriptions: [subscription]}) == expected_plan
      assert not is_nil(Billing.get_current_entitled_subscription(account)) == entitled?
      assert Billing.payment_failed?(account) == not entitled?
      assert Billing.get_current_active_subscription(account).id == subscription.id
    end
  end

  test "a null anchor written by an old replica has a bounded fallback, not an immediate cutoff" do
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    subscription = BillingFixtures.subscription_fixture(account_id: account.id, status: "past_due")
    assert Subscription.entitled?(subscription)
    assert Billing.effective_plan(account) == :pro

    expired =
      subscription
      |> Ecto.Changeset.change(updated_at: DateTime.to_naive(@cutoff))
      |> Repo.update!()

    assert is_nil(expired.past_due_since)
    refute Subscription.entitled?(expired)
    assert Billing.effective_plan(account) == :air
    assert Billing.payment_failed?(account)
  end

  test "an expired subscription cannot block a replacement that grants access" do
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    overdue = BillingFixtures.subscription_fixture(account_id: account.id, status: "past_due", past_due_since: @cutoff)
    replacement = BillingFixtures.subscription_fixture(account_id: account.id, status: "active", plan: :enterprise)

    assert Billing.effective_plan(account) == :enterprise
    assert Billing.effective_plan(%{account | subscriptions: [overdue, replacement]}) == :enterprise
    refute Billing.payment_failed?(account)
  end

  test "expiry enforces both cache allowance models without Stripe calls" do
    reject(&Stripe.Subscription.retrieve/1)

    for usage_based? <- [false, true] do
      account = AccountsFixtures.user_fixture(preload: [:account]).account
      stub(FeatureFlags, :usage_based_pricing_enabled?, fn _account -> usage_based? end)

      account =
        account
        |> Ecto.Changeset.change(
          current_month_remote_cache_hits_count: 1_000,
          current_month_cache_requests: UsagePricing.included_requests()
        )
        |> Repo.update!()

      subscription =
        BillingFixtures.subscription_fixture(account_id: account.id, status: "past_due", past_due_since: @cutoff)

      assert Billing.cache_access_blocked?(account)
      assert Billing.cache_blocked_account_ids([account]) == MapSet.new([account.id])
      assert Billing.payment_failed_account_ids([account.id]) == MapSet.new([account.id])

      subscription |> Ecto.Changeset.change(status: "active", past_due_since: nil) |> Repo.update!()
      refute Billing.cache_access_blocked?(account)
      assert Billing.cache_blocked_account_ids([account]) == MapSet.new()
      assert Billing.payment_failed_account_ids([account.id]) == MapSet.new()
    end
  end

  test "an overdue paid account is not sent an Air upgrade warning" do
    account =
      AccountsFixtures.user_fixture(
        preload: [:account],
        current_month_remote_cache_hits_count: Billing.get_payment_thresholds().remote_cache_hits
      ).account

    BillingFixtures.subscription_fixture(account_id: account.id, status: "past_due", past_due_since: @cutoff)

    assert {:ok, :ok} = AirUsageNotifications.enqueue(account.id, @now)
    refute_enqueued(worker: AirUsageNotificationWorker)
  end

  test "expiry preserves billing management and retention rather than creating another checkout" do
    account = AccountsFixtures.user_fixture(preload: [:account]).account

    subscription =
      BillingFixtures.subscription_fixture(account_id: account.id, status: "past_due", past_due_since: @cutoff)

    assert Billing.effective_plan(account) == :air
    assert RetentionPolicy.current_plan(account) == :pro
    assert RetentionPolicy.current_plans([account]) == %{account.id => :pro}
    reject(&Session.create/1)
    reject(&Stripe.Invoice.list/1)

    expect(Stripe.Subscription, :retrieve, fn id ->
      assert id == subscription.subscription_id
      {:ok, %Stripe.Subscription{items: %{data: [%{id: "old_usage"}, %{id: "old_flat"}]}}}
    end)

    expect(Stripe.Subscription, :update, fn id, %{items: items} ->
      assert id == subscription.subscription_id
      assert %{price: "air.usage"} in items
      {:ok, %{}}
    end)

    assert Billing.update_plan(%{plan: :air, account: account, success_url: "https://tuist.dev"}) == :ok
  end

  test "subscription projection and notification use a lock shared by independent database sessions" do
    parent = self()
    account_id = System.unique_integer([:positive])

    first =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Billing.with_subscription_lock(account_id, fn ->
            send(parent, {:first_locked, self()})
            receive do: (:release -> :ok)
          end)
        end)
      end)

    assert_receive {:first_locked, first_pid}, 5_000

    second =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          send(parent, :second_attempting)
          Billing.with_subscription_lock(account_id, fn -> send(parent, :second_locked) end)
        end)
      end)

    try do
      assert_receive :second_attempting, 5_000
      refute_receive :second_locked
      send(first_pid, :release)
      assert Task.await(first, 5_000) == {:ok, :ok}
      assert_receive :second_locked, 5_000
      Task.await(second, 5_000)
    after
      Task.shutdown(first, :brutal_kill)
      Task.shutdown(second, :brutal_kill)
    end
  end

  describe "webhook projection" do
    setup do
      user = AccountsFixtures.user_fixture(customer_id: "cus_grace", preload: [:account])
      stub(Stripe.Subscription, :retrieve, fn "sub_grace" -> {:ok, payload("past_due")} end)
      %{account: user.account}
    end

    test "anchors on the event time and retries cannot extend grace", %{account: account} do
      first = DateTime.to_unix(@cutoff)
      assert Billing.on_subscription_change(payload("past_due"), first) == :ok
      assert stored().past_due_since == @cutoff
      assert Billing.effective_plan(account) == :air

      assert Billing.on_subscription_change(payload("past_due"), first + 86_400) == :ok
      assert stored().past_due_since == @cutoff
      assert Billing.effective_plan(account) == :air
    end

    test "a recovery written by an older replica cannot carry its stale grace anchor into a new episode", %{
      account: account
    } do
      BillingFixtures.subscription_fixture(
        account_id: account.id,
        subscription_id: "sub_grace",
        status: "active",
        past_due_since: @cutoff,
        payment_grace_expiry_notified_at: @now
      )

      Billing.on_subscription_change(payload("past_due"), DateTime.to_unix(@now))
      assert stored().past_due_since == @now
      assert is_nil(stored().payment_grace_expiry_notified_at)
    end

    test "a live read discovering delinquency cannot anchor it to an unrelated historical event", %{account: account} do
      BillingFixtures.subscription_fixture(account_id: account.id, subscription_id: "sub_grace", status: "active")
      expect(Stripe.Subscription, :retrieve, fn "sub_grace" -> {:ok, payload("past_due")} end)

      Billing.on_subscription_change(payload("active"), DateTime.to_unix(@cutoff))
      assert stored().past_due_since == @now
      assert stored().stripe_event_created_at == @cutoff
      assert Billing.effective_plan(account) == :pro
    end

    test "legacy rows and later events predating the authoritative read are reconciled", %{account: account} do
      BillingFixtures.subscription_fixture(
        account_id: account.id,
        subscription_id: "sub_grace",
        status: "past_due",
        past_due_since: @cutoff
      )

      expect(Stripe.Subscription, :retrieve, fn "sub_grace" -> {:ok, payload("past_due")} end)
      Billing.on_subscription_change(payload("active"), DateTime.to_unix(@cutoff) - 86_400)
      assert stored().status == "past_due"
      assert Billing.effective_plan(account) == :air

      expect(Stripe.Subscription, :retrieve, fn "sub_grace" -> {:ok, payload("past_due")} end)
      Billing.on_subscription_change(payload("active"), DateTime.to_unix(@cutoff))
      assert stored().status == "past_due"
      assert stored().past_due_since == @cutoff
      assert Billing.effective_plan(account) == :air

      stored() |> Ecto.Changeset.change(updated_at: DateTime.to_naive(@now)) |> Repo.update!()
      expect(Stripe.Subscription, :retrieve, fn "sub_grace" -> {:ok, payload("past_due")} end)
      Billing.on_subscription_change(payload("active"), DateTime.to_unix(@now) + 10)
      assert stored().status == "past_due"
      assert stored().past_due_since == @cutoff
      assert Billing.effective_plan(account) == :air
    end

    test "older recovery and failure events cannot roll back state or restart grace", %{account: account} do
      first = DateTime.to_unix(@cutoff)
      Billing.on_subscription_change(payload("past_due"), first)
      Billing.on_subscription_change(payload("active"), first - 1)
      assert stored().past_due_since == @cutoff
      assert Billing.effective_plan(account) == :air

      expect(Stripe.Subscription, :retrieve, fn "sub_grace" -> {:ok, payload("active")} end)
      Billing.on_subscription_change(payload("active"), first + 1)
      assert is_nil(stored().past_due_since)
      assert Billing.effective_plan(account) == :pro

      Billing.on_subscription_change(payload("past_due"), first)
      assert stored().status == "active"
      assert is_nil(stored().past_due_since)
    end

    test "genuine recovery starts a fresh grace period and clears the previous notification marker" do
      first = DateTime.to_unix(@cutoff)
      Billing.on_subscription_change(payload("past_due"), first)
      stored() |> Ecto.Changeset.change(payment_grace_expiry_notified_at: @now) |> Repo.update!()

      expect(Stripe.Subscription, :retrieve, fn "sub_grace" -> {:ok, payload("active")} end)
      Billing.on_subscription_change(payload("active"), first + 1)
      assert is_nil(stored().payment_grace_expiry_notified_at)

      expect(Stripe.Subscription, :retrieve, fn "sub_grace" -> {:ok, payload("past_due")} end)
      Billing.on_subscription_change(payload("past_due"), first + 2)
      assert stored().past_due_since == @now
      assert is_nil(stored().payment_grace_expiry_notified_at)
    end

    test "same-second conflicting events reconcile with Stripe instead of trusting arrival order" do
      timestamp = DateTime.to_unix(@cutoff)
      Billing.on_subscription_change(payload("past_due"), timestamp)
      expect(Stripe.Subscription, :retrieve, fn "sub_grace" -> {:ok, payload("active")} end)
      assert Billing.on_subscription_change(payload("past_due"), timestamp) == :ok
      assert stored().status == "active"
      assert is_nil(stored().past_due_since)
    end

    test "a failed same-second reconciliation remains retryable and leaves stored state unchanged" do
      timestamp = DateTime.to_unix(@cutoff)
      Billing.on_subscription_change(payload("past_due"), timestamp)
      expect(Stripe.Subscription, :retrieve, fn "sub_grace" -> {:error, :timeout} end)

      assert_raise MatchError, fn -> Billing.on_subscription_change(payload("active"), timestamp) end
      assert stored().status == "past_due"
      assert stored().past_due_since == @cutoff
    end

    test "a null anchor is frozen from the persisted update time, not refreshed by the next retry", %{account: account} do
      subscription =
        BillingFixtures.subscription_fixture(account_id: account.id, status: "past_due", subscription_id: "sub_grace")

      subscription |> Ecto.Changeset.change(updated_at: DateTime.to_naive(@cutoff)) |> Repo.update!()
      Billing.on_subscription_change(payload("past_due"), DateTime.to_unix(@now))
      assert stored().past_due_since == @cutoff
      assert Billing.effective_plan(account) == :air
    end
  end

  defp stored, do: Repo.get_by!(Subscription, subscription_id: "sub_grace")

  defp payload(status) do
    %{
      id: "sub_grace",
      customer: "cus_grace",
      status: status,
      default_payment_method: nil,
      items: %{data: [%{price: %{id: "pro.usage"}}, %{price: %{id: "pro.flat"}}]}
    }
  end
end
