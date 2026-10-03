defmodule Tuist.Billing.AirRunnerUsageNotificationsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.UserNotifier
  alias Tuist.Billing.AirUsageNotification
  alias Tuist.Billing.AirUsageNotifications
  alias Tuist.Billing.Workers.AirUsageNotificationWorker
  alias Tuist.Runners.Allowance
  alias Tuist.Runners.Billing, as: RunnerBilling
  alias Tuist.Runners.RunnerSession
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  test "checks runner thresholds against the configured allowance" do
    stub(Allowance, :free_monthly_minutes, fn -> 10 end)

    for {minutes, expected} <- [{0, nil}, {7, nil}, {8, 80}, {9, 80}, {10, 100}, {12, 100}] do
      user = AccountsFixtures.user_fixture()
      stub(RunnerBilling, :compute_milliseconds, fn _, _, _ -> minutes * 60_000 end)
      assert {:ok, _} = AirUsageNotifications.enqueue(user.account.id, DateTime.utc_now())
      notification = Repo.get_by(AirUsageNotification, account_id: user.account.id, metric: :runner_minutes)
      assert (notification && notification.threshold) == expected
      if notification, do: assert(notification.limit == 10 && notification.usage == minutes)
    end
  end

  test "cache and runner thresholds notify independently and deduplicate independently" do
    user = AccountsFixtures.user_fixture(current_month_remote_cache_hits_count: 160)
    now = DateTime.utc_now()
    stub(RunnerBilling, :compute_milliseconds, fn _, _, _ -> 80 * 60_000 end)

    assert {:ok, _} = AirUsageNotifications.enqueue(user.account.id, now)
    assert {:ok, _} = AirUsageNotifications.enqueue(user.account.id, now)
    assert Repo.aggregate(AirUsageNotification, :count) == 2

    Accounts.update_account_current_month_usage(user.account.id, %{remote_cache_hits_count: 200})
    stub(RunnerBilling, :compute_milliseconds, fn _, _, _ -> 100 * 60_000 end)
    assert {:ok, _} = AirUsageNotifications.enqueue(user.account.id, now)
    assert {:ok, _} = AirUsageNotifications.enqueue(user.account.id, now)

    assert Repo.all(from(n in AirUsageNotification, select: {n.metric, n.threshold}, order_by: [n.metric, n.threshold])) ==
             [
               {:remote_cache_hits, 80},
               {:remote_cache_hits, 100},
               {:runner_minutes, 80},
               {:runner_minutes, 100}
             ]
  end

  test "notifies all admins but excludes ordinary organization members" do
    owner = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture(creator: owner)
    admin = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(admin, organization, role: :admin)
    Accounts.add_user_to_organization(AccountsFixtures.user_fixture(), organization, role: :user)
    Accounts.add_user_to_organization(AccountsFixtures.user_fixture(), organization, role: :viewer)
    stub(RunnerBilling, :compute_milliseconds, fn _, _, _ -> 80 * 60_000 end)

    assert {:ok, _} = AirUsageNotifications.enqueue(organization.account.id, DateTime.utc_now())
    assert Enum.sort(Enum.map(Repo.all(AirUsageNotification), & &1.user_id)) == Enum.sort([owner.id, admin.id])
  end

  test "active runner trials skip runner notifications without suppressing cache warnings" do
    user = AccountsFixtures.user_fixture(current_month_remote_cache_hits_count: 160)
    user.account |> change(runner_trial_started_at: DateTime.truncate(DateTime.utc_now(), :second)) |> Repo.update!()
    reject(RunnerBilling, :compute_milliseconds, 3)

    assert {:ok, _} = AirUsageNotifications.enqueue(user.account.id, DateTime.utc_now())
    assert [%{metric: :remote_cache_hits}] = Repo.all(AirUsageNotification)
  end

  test "ended runner trials are eligible again" do
    user = AccountsFixtures.user_fixture()
    now = DateTime.truncate(DateTime.utc_now(), :second)

    user.account
    |> change(runner_trial_started_at: DateTime.add(now, -1, :day), runner_trial_ended_at: now)
    |> Repo.update!()

    stub(RunnerBilling, :compute_milliseconds, fn _, _, _ -> 80 * 60_000 end)

    assert {:ok, _} = AirUsageNotifications.enqueue(user.account.id, now)
    assert [%{metric: :runner_minutes}] = Repo.all(AirUsageNotification)
  end

  test "paid accounts are excluded before querying runner usage" do
    user = AccountsFixtures.user_fixture()
    BillingFixtures.subscription_fixture(account_id: user.account.id, plan: :pro)
    reject(RunnerBilling, :compute_milliseconds, 3)
    assert {:ok, _} = AirUsageNotifications.enqueue(user.account.id, DateTime.utc_now())
    assert Repo.all(AirUsageNotification) == []
  end

  test "cache resets do not reset runner notifications, but a new month does" do
    user = AccountsFixtures.user_fixture()
    now = DateTime.utc_now()
    stub(RunnerBilling, :compute_milliseconds, fn _, _, _ -> 80 * 60_000 end)
    assert {:ok, _} = AirUsageNotifications.enqueue(user.account.id, now)
    notification = Repo.get_by!(AirUsageNotification, account_id: user.account.id)

    user.account |> change(free_tier_reset_at: DateTime.truncate(now, :second)) |> Repo.update!()
    assert {:ok, _} = AirUsageNotifications.enqueue(user.account.id, now)
    assert Repo.aggregate(AirUsageNotification, :count) == 1

    notification |> change(period_start: Timex.shift(notification.period_start, months: -1)) |> Repo.update!()
    assert {:ok, _} = AirUsageNotifications.enqueue(user.account.id, now)
    assert Repo.aggregate(AirUsageNotification, :count) == 2
  end

  test "uses normalized compute minutes rather than wall-clock minutes" do
    user = AccountsFixtures.user_fixture()
    started_at = ~U[2026-09-15 12:00:00.000000Z]
    ended_at = DateTime.add(started_at, 40, :minute)

    # Fix the query window so this test also works during the first minutes of a month.
    stub(RunnerBilling, :compute_milliseconds, fn account_id, _period_start, _period_end ->
      Mimic.call_original(RunnerBilling, :compute_milliseconds, [account_id, started_at, ended_at])
    end)

    Repo.insert!(%RunnerSession{
      account_id: user.account.id,
      workflow_job_id: System.unique_integer([:positive]),
      fleet_name: "tuist-macos",
      platform: :macos,
      vcpus: 12,
      memory_gb: 28,
      billing_multiplier: 20_000,
      started_at: started_at,
      job_started_at: started_at,
      job_ended_at: ended_at
    })

    assert {:ok, _} = AirUsageNotifications.enqueue(user.account.id, DateTime.utc_now())
    assert [%{metric: :runner_minutes, usage: 80, limit: 100, threshold: 80}] = Repo.all(AirUsageNotification)
  end

  test "delivers a runner warning once and suppresses it if a trial starts before delivery" do
    user = AccountsFixtures.user_fixture()
    stub(RunnerBilling, :compute_milliseconds, fn _, _, _ -> 80 * 60_000 end)
    {:ok, _} = AirUsageNotifications.enqueue(user.account.id, DateTime.utc_now())
    notification = Repo.get_by!(AirUsageNotification, account_id: user.account.id)

    expect(UserNotifier, :deliver_air_usage_notification, fn recipient, account, delivered ->
      assert recipient.id == user.id
      assert account.id == user.account.id
      assert delivered.metric == :runner_minutes
      {:ok, :email}
    end)

    assert :ok = perform_job(AirUsageNotificationWorker, %{notification_id: notification.id})
    assert Repo.reload!(notification).delivered_at
    assert :ok = perform_job(AirUsageNotificationWorker, %{notification_id: notification.id})

    stub(RunnerBilling, :compute_milliseconds, fn _, _, _ -> 100 * 60_000 end)
    {:ok, _} = AirUsageNotifications.enqueue(user.account.id, DateTime.utc_now())
    reached = Repo.get_by!(AirUsageNotification, account_id: user.account.id, threshold: 100)
    user.account |> change(runner_trial_started_at: DateTime.truncate(DateTime.utc_now(), :second)) |> Repo.update!()
    reject(UserNotifier, :deliver_air_usage_notification, 3)
    assert :ok = perform_job(AirUsageNotificationWorker, %{notification_id: reached.id})
    refute Repo.reload!(reached).delivered_at
  end
end
