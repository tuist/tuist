defmodule Tuist.Billing.AirUsageNotificationsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Accounts
  alias Tuist.Billing.AirUsageNotification
  alias Tuist.Billing.AirUsageNotifications
  alias Tuist.Billing.Workers.AirUsageNotificationWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  test "notifies every admin, excluding ordinary members and viewers" do
    owner = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture(creator: owner)
    set_cache_requests(organization.account.id, 800_000)
    admin = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(admin, organization, role: :admin)

    for role <- [:user, :viewer] do
      Accounts.add_user_to_organization(AccountsFixtures.user_fixture(), organization, role: role)
    end

    assert {:ok, _} = AirUsageNotifications.enqueue(organization.account.id, DateTime.utc_now())
    notifications = Repo.all(AirUsageNotification)
    assert Enum.sort(Enum.map(notifications, & &1.user_id)) == Enum.sort([owner.id, admin.id])

    assert Enum.all?(
             notifications,
             &(&1.metric == :cache_requests && &1.threshold == 80 && &1.usage == 800_000 && &1.limit == 1_000_000)
           )

    assert length(all_enqueued(worker: AirUsageNotificationWorker)) == 2
  end

  test "notifies personal account owners at each threshold once, even after jobs are pruned" do
    user = cache_requests_user(800_000)
    now = DateTime.utc_now()
    assert {:ok, _} = AirUsageNotifications.enqueue(user.account.id, now)
    Repo.update_all(AirUsageNotification, set: [delivered_at: DateTime.truncate(now, :second)])
    Repo.delete_all(Oban.Job)
    assert {:ok, _} = AirUsageNotifications.enqueue(user.account.id, now)
    refute_enqueued(worker: AirUsageNotificationWorker)

    set_cache_requests(user.account.id, 1_000_000)
    assert {:ok, _} = AirUsageNotifications.enqueue(user.account.id, now)
    assert {:ok, _} = AirUsageNotifications.enqueue(user.account.id, now)
    assert Enum.sort(Enum.map(Repo.all(AirUsageNotification), & &1.threshold)) == [80, 100]
    assert length(all_enqueued(worker: AirUsageNotificationWorker)) == 1
  end

  test "requeues undelivered notifications after terminal jobs or pruning" do
    for state <- ["completed", "cancelled", "discarded", :pruned] do
      user = cache_requests_user(800_000)
      now = DateTime.utc_now()
      {:ok, _} = AirUsageNotifications.enqueue(user.account.id, now)
      notification = Repo.get_by!(AirUsageNotification, account_id: user.account.id)
      jobs = from(j in Oban.Job, where: j.args == ^%{"notification_id" => notification.id})

      if state == :pruned, do: Repo.delete_all(jobs), else: Repo.update_all(jobs, set: [state: state])

      assert {:ok, _} = AirUsageNotifications.enqueue(user.account.id, now)
      assert_enqueued(worker: AirUsageNotificationWorker, args: %{notification_id: notification.id})
      assert Repo.aggregate(from(n in AirUsageNotification, where: n.account_id == ^user.account.id), :count) == 1
    end
  end

  test "does not enqueue a duplicate while delivery is active or awaiting retry" do
    user = cache_requests_user(800_000)
    now = DateTime.utc_now()
    {:ok, _} = AirUsageNotifications.enqueue(user.account.id, now)
    notification = Repo.get_by!(AirUsageNotification, account_id: user.account.id)
    jobs = from(j in Oban.Job, where: j.args == ^%{"notification_id" => notification.id})

    for state <- ["available", "scheduled", "executing", "retryable"] do
      Repo.update_all(jobs, set: [state: state])
      assert {:ok, _} = AirUsageNotifications.enqueue(user.account.id, now)
      assert Repo.aggregate(jobs, :count) == 1
    end
  end

  test "ignores nil and below-threshold usage and handles exact boundaries and overshoots" do
    for {usage, expected} <- [
          {nil, nil},
          {0, nil},
          {799_999, nil},
          {800_000, 80},
          {999_999, 80},
          {1_000_000, 100},
          {1_200_000, 100}
        ] do
      user = AccountsFixtures.user_fixture()

      user.account
      |> change(current_month_cache_egress_megabytes: 0, current_month_cache_requests: usage)
      |> Repo.update!()

      assert {:ok, _} = AirUsageNotifications.enqueue(user.account.id, DateTime.utc_now())
      notification = Repo.get_by(AirUsageNotification, account_id: user.account.id)
      assert (notification && notification.threshold) == expected
    end
  end

  test "excludes active and trialing paid and open-source plans" do
    for plan <- [:pro, :enterprise, :open_source], status <- ["active", "trialing"] do
      user = cache_requests_user(1_000_000)
      BillingFixtures.subscription_fixture(account_id: user.account.id, plan: plan, status: status)
      assert {:ok, _} = AirUsageNotifications.enqueue(user.account.id, DateTime.utc_now())
    end

    assert Repo.all(AirUsageNotification) == []
    refute_enqueued(worker: AirUsageNotificationWorker)
  end

  test "notifies accounts whose paid subscription has lapsed" do
    user = cache_requests_user(1_000_000)
    BillingFixtures.subscription_fixture(account_id: user.account.id, plan: :pro, status: "canceled")
    assert {:ok, _} = AirUsageNotifications.enqueue(user.account.id, DateTime.utc_now())
    assert Repo.get_by!(AirUsageNotification, account_id: user.account.id).threshold == 100
  end

  test "sends only the reached-limit notification when usage jumps over both thresholds" do
    user = cache_requests_user(1_150_000)
    assert {:ok, _} = AirUsageNotifications.enqueue(user.account.id, DateTime.utc_now())
    assert [%{threshold: 100}] = Repo.all(AirUsageNotification)
  end

  test "a new calendar month or free-tier reset allows another notification" do
    user = cache_requests_user(800_000)
    now = DateTime.utc_now()
    assert {:ok, _} = AirUsageNotifications.enqueue(user.account.id, now)
    notification = Repo.get_by!(AirUsageNotification, account_id: user.account.id)

    notification
    |> change(period_start: Timex.shift(notification.period_start, months: -1))
    |> Repo.update!()

    assert {:ok, _} = AirUsageNotifications.enqueue(user.account.id, now)
    assert Repo.aggregate(AirUsageNotification, :count) == 2

    user.account |> change(free_tier_reset_at: DateTime.truncate(now, :second)) |> Repo.update!()
    assert {:ok, _} = AirUsageNotifications.enqueue(user.account.id, now)
    assert Repo.aggregate(AirUsageNotification, :count) == 3
  end

  test "warns about the cache allowances" do
    user = AccountsFixtures.user_fixture()

    Accounts.update_account_current_month_usage(user.account.id, %{
      cache_egress_megabytes: 85_000,
      cache_requests: 100_000
    })

    assert {:ok, _} = AirUsageNotifications.enqueue(user.account.id, DateTime.utc_now())

    assert [%{metric: :cache_egress_megabytes, threshold: 80, usage: 85_000, limit: 100_000}] =
             Repo.all(AirUsageNotification)
  end

  test "does not notify for a refresh from a previous month" do
    user = cache_requests_user(1_000_000)
    assert {:ok, _} = AirUsageNotifications.enqueue(user.account.id, Timex.shift(DateTime.utc_now(), months: -1))
    assert Repo.all(AirUsageNotification) == []
  end

  defp cache_requests_user(requests) do
    user = AccountsFixtures.user_fixture()
    set_cache_requests(user.account.id, requests)
    user
  end

  defp set_cache_requests(account_id, requests) do
    Accounts.update_account_current_month_usage(account_id, %{cache_requests: requests})
  end
end
