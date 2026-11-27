defmodule Tuist.Runners.PrepaidNotificationsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.UserNotifier
  alias Tuist.Billing
  alias Tuist.Billing.Subscription
  alias Tuist.Environment
  alias Tuist.Runners.Allowance
  alias Tuist.Runners.Prepaid
  alias Tuist.Runners.PrepaidActivation
  alias Tuist.Runners.PrepaidNotification
  alias Tuist.Runners.PrepaidNotifications
  alias Tuist.Runners.PrepaidTopUp
  alias Tuist.Runners.RunnerSession
  alias Tuist.Runners.Workers.PrepaidNotificationWorker
  alias Tuist.Runners.Workers.PrepaidUsageWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  setup do
    now = DateTime.truncate(DateTime.utc_now(), :second)
    user = AccountsFixtures.user_fixture()
    account = user.account |> change(runner_trial_started_at: nil, runner_trial_ended_at: nil) |> Repo.update!()
    cycle_start = DateTime.add(now, -20, :day)
    cycle_end = DateTime.add(now, 10, :day)

    BillingFixtures.subscription_fixture(
      account_id: account.id,
      current_period_start: cycle_start,
      current_period_end: cycle_end
    )

    activation = pool(account, now)
    %{user: user, account: account, activation: activation, now: now, cycle_start: cycle_start, cycle_end: cycle_end}
  end

  test "exact thresholds, overshoot and credit multiplier budget", %{activation: activation} do
    for {usage, threshold} <- [{0, nil}, {799, nil}, {800, 80}, {999, 80}, {1000, 100}, {1500, 100}] do
      assert PrepaidNotifications.threshold(usage, 1000) == threshold
    end

    activation = %{
      activation
      | request: Map.merge(activation.request, %{"paid_cents" => 1001, "credit_multiplier" => "1.2345"})
    }

    assert PrepaidNotifications.budget_cents(activation) == 1235
  end

  test "the budget includes the pool's applied top-ups at each grant's own multiplier", context do
    %{account: account, activation: activation} = context

    top_up = fn status, grants ->
      Repo.insert!(%PrepaidTopUp{
        account_id: account.id,
        activation_id: activation.id,
        change_id: Ecto.UUID.generate(),
        status: status,
        principal: %{},
        before: %{},
        request: %{"grants" => grants}
      })
    end

    top_up.("applied", [
      %{"platform" => "macos", "paid_cents" => 1000, "credit_multiplier" => "1.1843"},
      %{"platform" => "linux", "paid_cents" => 500, "credit_multiplier" => "1"}
    ])

    # A pending top-up has granted nothing yet.
    top_up.("pending", [%{"platform" => "macos", "paid_cents" => 9000, "credit_multiplier" => "1"}])

    assert PrepaidNotifications.budget_cents(activation) == 1000 + 1184 + 500
  end

  test "pre-activation paid usage spends free tier first, separately per purchased platform", context do
    %{account: account, activation: activation, now: now, cycle_start: cycle_start} = context
    before = DateTime.add(activation.activated_at, -3, :day)
    session(account, :macos, cycle_start, 90)
    session(account, :linux, before, 2490)
    session(account, :macos, activation.activated_at, 30)
    session(account, :linux, activation.activated_at, 60)

    macos = 20 * 60_000
    linux = 50 * 60_000
    expected = cost(:macos, macos) + cost(:linux, linux)
    assert PrepaidNotifications.usage_cents(activation, account, now) == expected

    activation = %{activation | request: Map.put(activation.request, "platforms", ["linux"])}
    assert PrepaidNotifications.usage_cents(activation, account, now) == cost(:linux, linux)
  end

  test "macOS and Linux spending together trigger the shared pool warning", context do
    %{account: account, activation: activation, now: now} = context
    # After the independent free tiers: 100 macOS minutes cost $5,
    # and 1,250 Linux baseline minutes cost $3, reaching 80% of $10.
    session(account, :macos, activation.activated_at, 200)
    assert PrepaidNotifications.usage_cents(activation, account, now) == 500
    assert {:ok, _} = PrepaidNotifications.enqueue(activation.id)
    assert Repo.all(PrepaidNotification) == []

    session(account, :linux, activation.activated_at, 3750)
    assert PrepaidNotifications.usage_cents(activation, account, now) == 800
    assert {:ok, _} = PrepaidNotifications.enqueue(activation.id)
    assert [%{threshold: 80, usage_cents: 800, budget_cents: 1000}] = Repo.all(PrepaidNotification)
  end

  test "a pool covering cache usage counts it past the allowances earlier usage spent", context do
    %{account: account, activation: activation, now: now, cycle_start: cycle_start} = context

    stub(Billing.UsagePricing, :metered_cache_usage, fn _account_id, period_start, _period_end ->
      if period_start == cycle_start,
        do: %{egress_megabytes: 90_000, requests: 900_000},
        else: %{egress_megabytes: 30_000, requests: 300_000}
    end)

    # 20 GB past 100 GB at $0.10 and 200,000 requests past 1M at $0.01 per 1,000.
    covering = %{activation | request: Map.put(activation.request, "covers_cache", true)}
    assert PrepaidNotifications.usage_cents(covering, account, now) == 400
    assert PrepaidNotifications.usage_cents(activation, account, now) == 0
  end

  test "trial usage is excluded and does not consume free allowance", context do
    %{account: account, activation: activation, now: now, cycle_start: cycle_start} = context
    trial_end = DateTime.add(activation.activated_at, 1, :day)
    account = account |> change(runner_trial_started_at: cycle_start, runner_trial_ended_at: trial_end) |> Repo.update!()
    session(account, :macos, activation.activated_at, 300)
    session(account, :macos, trial_end, 120)
    assert PrepaidNotifications.usage_cents(activation, account, now) == cost(:macos, 20 * 60_000)
  end

  test "monthly allowances reset on the subscription anchor, not activation", context do
    %{account: account, activation: activation, now: now, cycle_start: cycle_start, cycle_end: cycle_end} = context
    previous_start = Timex.shift(cycle_start, months: -1)

    activation = %{
      activation
      | activated_at: DateTime.add(previous_start, 1, :day),
        request: Map.put(activation.request, "starts_on", Date.to_iso8601(DateTime.to_date(previous_start)))
    }

    stub(Billing, :recent_billing_periods, fn _, 14 -> [{cycle_start, cycle_end}, {previous_start, cycle_start}] end)
    session(account, :macos, activation.activated_at, 120)
    session(account, :macos, cycle_start, 130)
    assert PrepaidNotifications.usage_cents(activation, account, now) == cost(:macos, 50 * 60_000)
  end

  test "clips job usage at activation, trial and inclusive expiry, never charges Pod idle time", context do
    %{account: account, activation: activation, now: now, cycle_start: cycle_start, cycle_end: cycle_end} = context
    expiry = Date.add(DateTime.to_date(now), -1)
    midnight = expiry |> Date.add(1) |> DateTime.new!(~T[00:00:00], "Etc/UTC")

    activation = %{
      activation
      | activated_at: DateTime.add(midnight, -30, :minute),
        request: Map.put(activation.request, "expires_on", Date.to_iso8601(expiry))
    }

    stub(Billing, :recent_billing_periods, fn _, 14 -> [{cycle_start, cycle_end}] end)
    stub(Allowance, :free_monthly_minutes, fn _ -> 0 end)
    session(account, :macos, DateTime.add(activation.activated_at, -10, :minute), 50)

    Repo.insert!(%RunnerSession{
      account_id: account.id,
      workflow_job_id: System.unique_integer([:positive]),
      fleet_name: "idle",
      platform: :macos,
      started_at: %{cycle_start | microsecond: {0, 6}},
      ended_at: %{now | microsecond: {0, 6}},
      billing_multiplier: 10_000
    })

    assert PrepaidNotifications.usage_cents(activation, account, now) == cost(:macos, 30 * 60_000)
  end

  test "rounds only the combined total, not each platform or cycle", context do
    %{account: account, activation: activation, now: now} = context
    stub(Allowance, :free_monthly_minutes, fn _ -> 0 end)
    # 0.6 macOS cents + 0.48 Linux cents = one cent, not zero.
    session(account, :macos, activation.activated_at, 0.12)
    session(account, :linux, activation.activated_at, 2)
    assert PrepaidNotifications.usage_cents(activation, account, now) == 1
  end

  test "completed deliveries survive job pruning; discarded and failed deliveries reopen independently", context do
    %{activation: activation, user: user} = context
    set_usage(activation, 800)
    assert {:ok, _} = PrepaidNotifications.enqueue(activation.id)
    assert {:ok, _} = PrepaidNotifications.enqueue(activation.id)
    assert [%{threshold: 80} = notification] = Repo.all(PrepaidNotification)
    assert length(all_enqueued(worker: PrepaidNotificationWorker)) == 1

    expect(UserNotifier, :deliver_runner_prepaid_notification, fn recipient, _, _ ->
      assert recipient.id == user.id
      {:error, :smtp_timeout}
    end)

    assert {:error, :smtp_timeout} = perform_job(PrepaidNotificationWorker, %{notification_id: notification.id})
    refute Repo.reload!(notification).delivered_at
    Repo.update_all(Oban.Job, set: [state: "discarded"])
    assert {:ok, _} = PrepaidNotifications.enqueue(activation.id)
    assert_enqueued(worker: PrepaidNotificationWorker, args: %{notification_id: notification.id})

    expect(UserNotifier, :deliver_runner_prepaid_notification, fn _, _, _ -> {:ok, :email} end)
    assert :ok = perform_job(PrepaidNotificationWorker, %{notification_id: notification.id})
    assert Repo.reload!(notification).delivered_at
    assert :ok = perform_job(PrepaidNotificationWorker, %{notification_id: notification.id})
    Repo.delete_all(Oban.Job)
    assert {:ok, _} = PrepaidNotifications.enqueue(activation.id)
    refute_enqueued(worker: PrepaidNotificationWorker)
  end

  test "jumping to exhaustion queues only exhaustion and drops a previously queued warning", %{activation: activation} do
    set_usage(activation, 800)
    {:ok, _} = PrepaidNotifications.enqueue(activation.id)
    warning = Repo.one!(PrepaidNotification)
    set_usage(activation, 1100)
    {:ok, _} = PrepaidNotifications.enqueue(activation.id)
    reject(UserNotifier, :deliver_runner_prepaid_notification, 3)
    assert :ok = perform_job(PrepaidNotificationWorker, %{notification_id: warning.id})
    refute Repo.reload!(warning).delivered_at
    assert Repo.get_by!(PrepaidNotification, threshold: 100)
  end

  test "actual job usage observes exact thresholds and a direct exhaustion never queues 80%", context do
    %{activation: activation, account: account, now: now} = context
    set_usage(activation, 799)
    {:ok, _} = PrepaidNotifications.enqueue(activation.id)
    assert Repo.all(PrepaidNotification) == []
    set_usage(activation, 800)
    {:ok, _} = PrepaidNotifications.enqueue(activation.id)
    assert [%{threshold: 80}] = Repo.all(PrepaidNotification)
    set_usage(activation, 1000)
    {:ok, _} = PrepaidNotifications.enqueue(activation.id)
    assert Repo.get_by!(PrepaidNotification, activation_id: activation.id, threshold: 100)

    second_pool = pool(account, now)
    set_usage(second_pool, 1200)
    {:ok, _} = PrepaidNotifications.enqueue(second_pool.id)
    assert [%{threshold: 100}] = Repo.all(from(n in PrepaidNotification, where: n.activation_id == ^second_pool.id))
  end

  test "delivery rechecks pool expiry and subscription status", %{activation: activation, account: account, now: now} do
    set_usage(activation, 800)
    {:ok, _} = PrepaidNotifications.enqueue(activation.id)
    notification = Repo.one!(PrepaidNotification)
    reject(UserNotifier, :deliver_runner_prepaid_notification, 3)

    expired_request =
      Map.put(activation.request, "expires_on", now |> DateTime.to_date() |> Date.add(-1) |> Date.to_iso8601())

    expired = activation |> change(request: expired_request) |> Repo.update!()
    assert :ok = perform_job(PrepaidNotificationWorker, %{notification_id: notification.id})
    expired |> change(request: activation.request) |> Repo.update!()
    Repo.update_all(from(s in Subscription, where: s.account_id == ^account.id), set: [status: "canceled"])
    assert :ok = perform_job(PrepaidNotificationWorker, %{notification_id: notification.id})
    refute Repo.reload!(notification).delivered_at
  end

  test "the last contract day is inclusive, but midnight after expiry is inactive", context do
    %{activation: activation, account: account} = context

    midnight =
      activation.request["expires_on"] |> Date.from_iso8601!() |> Date.add(1) |> DateTime.new!(~T[00:00:00], "Etc/UTC")

    assert PrepaidNotifications.active?(activation, account, DateTime.add(midnight, -1, :second))
    refute PrepaidNotifications.active?(activation, account, midnight)
  end

  test "notices use purchased dollars, cap prepaid consumption and keep billing links", %{
    user: user,
    account: account,
    activation: activation
  } do
    stub(Environment, :mailing_from_address, fn -> "noreply@tuist.dev" end)
    stub(Environment, :mailing_reply_to_address, fn -> nil end)

    activation = %{activation | request: Map.put(activation.request, "paid_cents", 625_000)}

    for {threshold, usage, consumed} <- [{80, 555_600, "$5,000.00"}, {100, 700_000, "$6,250.00"}] do
      {:ok, email} =
        UserNotifier.deliver_runner_prepaid_notification(user, account, %{
          activation: activation,
          threshold: threshold,
          usage_cents: usage,
          budget_cents: 694_500
        })

      assert email.to == [nil: user.email]
      assert email.subject =~ "#{threshold}%"
      assert email.text_body =~ "standard on-demand rates"
      assert email.text_body =~ "/#{account.name}/billing"
      assert email.text_body =~ consumed
      assert email.text_body =~ "$6,250.00"
      refute email.text_body =~ "6945"
      assert is_nil(email.html_body)
    end
  end

  test "expired, pending, future and inactive pools are never notified", context do
    %{account: account, activation: activation, now: now} = context
    set_usage(activation, 1200)

    for attrs <- [
          [status: "pending"],
          [activated_at: DateTime.add(now, 1, :day)],
          [
            request:
              Map.put(activation.request, "starts_on", now |> DateTime.to_date() |> Date.add(1) |> Date.to_iso8601())
          ],
          [
            request:
              Map.put(activation.request, "expires_on", now |> DateTime.to_date() |> Date.add(-1) |> Date.to_iso8601())
          ]
        ] do
      altered = activation |> change(attrs) |> Repo.update!()
      assert {:ok, _} = PrepaidNotifications.enqueue(altered.id)
      altered |> change(Map.new(attrs, fn {key, _} -> {key, Map.fetch!(activation, key)} end)) |> Repo.update!()
    end

    Repo.update_all(from(s in Subscription, where: s.account_id == ^account.id), set: [status: "canceled"])
    assert {:ok, _} = PrepaidNotifications.enqueue(activation.id)
    assert Repo.all(PrepaidNotification) == []
  end

  test "admin retries do not resend to successful admins and losing access skips delivery", %{now: now} do
    owner = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture(creator: owner)
    admin = AccountsFixtures.user_fixture()
    member = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(admin, organization, role: :admin)
    Accounts.add_user_to_organization(member, organization, role: :user)
    account = organization.account |> change(runner_trial_started_at: nil) |> Repo.update!()
    BillingFixtures.subscription_fixture(account_id: account.id)
    activation = pool(account, now)
    set_usage(activation, 1000)
    {:ok, _} = PrepaidNotifications.enqueue(activation.id)
    notices = Repo.all(from(n in PrepaidNotification, where: n.activation_id == ^activation.id))
    assert Enum.sort(Enum.map(notices, & &1.user_id)) == Enum.sort([owner.id, admin.id])
    owner_notice = Enum.find(notices, &(&1.user_id == owner.id))
    admin_notice = Enum.find(notices, &(&1.user_id == admin.id))
    expect(UserNotifier, :deliver_runner_prepaid_notification, fn _, _, _ -> {:ok, :email} end)
    assert :ok = perform_job(PrepaidNotificationWorker, %{notification_id: owner_notice.id})
    expect(UserNotifier, :deliver_runner_prepaid_notification, fn _, _, _ -> {:error, :timeout} end)
    assert {:error, :timeout} = perform_job(PrepaidNotificationWorker, %{notification_id: admin_notice.id})
    assert :ok = perform_job(PrepaidNotificationWorker, %{notification_id: owner_notice.id})
    Accounts.update_user_role_in_organization(admin, organization, :user)
    reject(UserNotifier, :deliver_runner_prepaid_notification, 3)
    assert :ok = perform_job(PrepaidNotificationWorker, %{notification_id: admin_notice.id})
    refute Repo.reload!(admin_notice).delivered_at
  end

  test "scanner bounds fanout and queues a durable continuation", %{account: account, activation: activation, now: now} do
    for _ <- 1..100, do: pool(account, now)
    assert :ok = perform_job(PrepaidUsageWorker, %{})
    jobs = all_enqueued(worker: PrepaidUsageWorker)
    activation_ids = for %{args: %{"activation_id" => id}} <- jobs, do: id
    assert length(activation_ids) == 100
    assert activation.id in activation_ids
    assert [%{args: %{"after_id" => after_id}}] = Enum.filter(jobs, &Map.has_key?(&1.args, "after_id"))
    assert :ok = perform_job(PrepaidUsageWorker, %{after_id: after_id})
    assert length(all_enqueued(worker: PrepaidUsageWorker)) == 102
  end

  defp pool(account, now) do
    activated_at = DateTime.add(now, -5, :day)

    Repo.insert!(%PrepaidActivation{
      account_id: account.id,
      change_id: Ecto.UUID.generate(),
      status: "applied",
      activated_at: activated_at,
      principal: %{},
      before: %{},
      grant_id: "credgr_test",
      subscription_schedule_id: "sub_sched_test",
      request: %{
        "starts_on" => activated_at |> DateTime.to_date() |> Date.to_iso8601(),
        "expires_on" => now |> DateTime.to_date() |> Date.add(30) |> Date.to_iso8601(),
        "paid_cents" => 1000,
        "credit_multiplier" => "1",
        "platforms" => ["macos", "linux"]
      }
    })
  end

  defp session(account, platform, started_at, minutes) do
    started_at = %{started_at | microsecond: {elem(started_at.microsecond, 0), 6}}
    ended_at = DateTime.add(started_at, round(minutes * 60_000), :millisecond)

    Repo.insert!(%RunnerSession{
      account_id: account.id,
      workflow_job_id: System.unique_integer([:positive]),
      fleet_name: "prepaid-test",
      platform: platform,
      vcpus: 8,
      memory_gb: 24,
      billing_multiplier: 10_000,
      started_at: DateTime.add(started_at, -1, :hour),
      ended_at: DateTime.add(ended_at, 1, :hour),
      job_started_at: started_at,
      job_ended_at: ended_at
    })
  end

  defp set_usage(activation, cents) do
    Repo.delete_all(from(s in RunnerSession, where: s.account_id == ^activation.account_id))

    session(
      %{id: activation.account_id},
      :macos,
      activation.activated_at,
      Allowance.free_monthly_minutes(:macos) + cents / cost(:macos, 60_000)
    )
  end

  defp cost(platform, ms), do: Prepaid.on_demand_cost_for_milliseconds(platform, ms).amount
end
