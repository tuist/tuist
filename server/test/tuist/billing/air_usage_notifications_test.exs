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
    organization = AccountsFixtures.organization_fixture(creator: owner, current_month_remote_cache_hits_count: 160)
    admin = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(admin, organization, role: :admin)

    for role <- [:user, :viewer] do
      Accounts.add_user_to_organization(AccountsFixtures.user_fixture(), organization, role: role)
    end

    assert {:ok, _} = AirUsageNotifications.enqueue(organization.account.id, DateTime.utc_now())
    notifications = Repo.all(AirUsageNotification)
    assert Enum.sort(Enum.map(notifications, & &1.user_id)) == Enum.sort([owner.id, admin.id])
    assert Enum.all?(notifications, &(&1.threshold == 80 && &1.usage == 160 && &1.limit == 200))
    assert length(all_enqueued(worker: AirUsageNotificationWorker)) == 2
  end

  test "notifies personal account owners at each threshold once, even after jobs are pruned" do
    user = AccountsFixtures.user_fixture(current_month_remote_cache_hits_count: 160)
    now = DateTime.utc_now()
    assert {:ok, _} = AirUsageNotifications.enqueue(user.account.id, now)
    Repo.delete_all(Oban.Job)
    assert {:ok, _} = AirUsageNotifications.enqueue(user.account.id, now)
    refute_enqueued(worker: AirUsageNotificationWorker)

    Accounts.update_account_current_month_usage(user.account.id, %{remote_cache_hits_count: 200})
    assert {:ok, _} = AirUsageNotifications.enqueue(user.account.id, now)
    assert {:ok, _} = AirUsageNotifications.enqueue(user.account.id, now)
    assert Enum.sort(Enum.map(Repo.all(AirUsageNotification), & &1.threshold)) == [80, 100]
    assert length(all_enqueued(worker: AirUsageNotificationWorker)) == 1
  end

  test "ignores nil and below-threshold usage and handles exact boundaries and overshoots" do
    for {usage, expected} <- [{nil, nil}, {0, nil}, {159, nil}, {160, 80}, {199, 80}, {200, 100}, {240, 100}] do
      user = AccountsFixtures.user_fixture(current_month_remote_cache_hits_count: usage)
      assert {:ok, _} = AirUsageNotifications.enqueue(user.account.id, DateTime.utc_now())
      notification = Repo.get_by(AirUsageNotification, account_id: user.account.id)
      assert (notification && notification.threshold) == expected
    end
  end

  test "excludes active and trialing paid and open-source plans" do
    for plan <- [:pro, :enterprise, :open_source], status <- ["active", "trialing"] do
      user = AccountsFixtures.user_fixture(current_month_remote_cache_hits_count: 200)
      BillingFixtures.subscription_fixture(account_id: user.account.id, plan: plan, status: status)
      assert {:ok, _} = AirUsageNotifications.enqueue(user.account.id, DateTime.utc_now())
    end

    assert Repo.all(AirUsageNotification) == []
    refute_enqueued(worker: AirUsageNotificationWorker)
  end

  test "notifies accounts whose paid subscription has lapsed" do
    user = AccountsFixtures.user_fixture(current_month_remote_cache_hits_count: 200)
    BillingFixtures.subscription_fixture(account_id: user.account.id, plan: :pro, status: "canceled")
    assert {:ok, _} = AirUsageNotifications.enqueue(user.account.id, DateTime.utc_now())
    assert Repo.get_by!(AirUsageNotification, account_id: user.account.id).threshold == 100
  end

  test "sends only the reached-limit notification when usage jumps over both thresholds" do
    user = AccountsFixtures.user_fixture(current_month_remote_cache_hits_count: 230)
    assert {:ok, _} = AirUsageNotifications.enqueue(user.account.id, DateTime.utc_now())
    assert [%{threshold: 100}] = Repo.all(AirUsageNotification)
  end

  test "a new calendar month or free-tier reset allows another notification" do
    user = AccountsFixtures.user_fixture(current_month_remote_cache_hits_count: 160)
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

  test "does not notify for a refresh from a previous month" do
    user = AccountsFixtures.user_fixture(current_month_remote_cache_hits_count: 200)
    assert {:ok, _} = AirUsageNotifications.enqueue(user.account.id, Timex.shift(DateTime.utc_now(), months: -1))
    assert Repo.all(AirUsageNotification) == []
  end
end
