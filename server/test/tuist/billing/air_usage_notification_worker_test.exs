defmodule Tuist.Billing.Workers.AirUsageNotificationWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.UserNotifier
  alias Tuist.Billing.AirUsageNotification
  alias Tuist.Billing.AirUsageNotifications
  alias Tuist.Billing.Workers.AirUsageNotificationWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  setup do
    user = AccountsFixtures.user_fixture(current_month_remote_cache_hits_count: 160)
    {:ok, _} = AirUsageNotifications.enqueue(user.account.id, DateTime.utc_now())
    notification = Repo.get_by!(AirUsageNotification, account_id: user.account.id)
    %{user: user, notification: notification}
  end

  test "records success and does not redeliver a completed notification", %{user: user, notification: notification} do
    expect(UserNotifier, :deliver_air_usage_notification, fn recipient, account, delivered ->
      assert recipient.id == user.id
      assert account.id == user.account.id
      assert delivered.id == notification.id
      {:ok, :email}
    end)

    assert :ok = perform_job(AirUsageNotificationWorker, %{notification_id: notification.id})
    assert Repo.reload!(notification).delivered_at
    assert :ok = perform_job(AirUsageNotificationWorker, %{notification_id: notification.id})
  end

  test "returns delivery failures to Oban and allows retry", %{notification: notification} do
    expect(UserNotifier, :deliver_air_usage_notification, fn _, _, _ -> {:error, :smtp_timeout} end)
    assert {:error, :smtp_timeout} = perform_job(AirUsageNotificationWorker, %{notification_id: notification.id})
    refute Repo.reload!(notification).delivered_at

    expect(UserNotifier, :deliver_air_usage_notification, fn _, _, _ -> {:ok, :email} end)
    assert :ok = perform_job(AirUsageNotificationWorker, %{notification_id: notification.id})
    assert Repo.reload!(notification).delivered_at
  end

  test "skips accounts upgraded before delivery", %{user: user, notification: notification} do
    BillingFixtures.subscription_fixture(account_id: user.account.id, plan: :pro)
    reject(UserNotifier, :deliver_air_usage_notification, 3)
    assert :ok = perform_job(AirUsageNotificationWorker, %{notification_id: notification.id})
    refute Repo.reload!(notification).delivered_at
  end

  test "skips stale warnings once the account reaches 100%", %{user: user, notification: notification} do
    Accounts.update_account_current_month_usage(user.account.id, %{remote_cache_hits_count: 200})
    reject(UserNotifier, :deliver_air_usage_notification, 3)
    assert :ok = perform_job(AirUsageNotificationWorker, %{notification_id: notification.id})
  end

  test "skips notifications after the month ends or the allowance resets", %{notification: notification, user: user} do
    notification |> change(period_start: Timex.shift(notification.period_start, months: -1)) |> Repo.update!()
    reject(UserNotifier, :deliver_air_usage_notification, 3)
    assert :ok = perform_job(AirUsageNotificationWorker, %{notification_id: notification.id})

    notification |> Repo.reload!() |> change(period_start: notification.period_start) |> Repo.update!()
    user.account |> change(free_tier_reset_at: DateTime.truncate(DateTime.utc_now(), :second)) |> Repo.update!()
    assert :ok = perform_job(AirUsageNotificationWorker, %{notification_id: notification.id})
  end

  test "skips recipients who are no longer admins" do
    organization = AccountsFixtures.organization_fixture(current_month_remote_cache_hits_count: 160)
    admin = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(admin, organization, role: :admin)
    {:ok, _} = AirUsageNotifications.enqueue(organization.account.id, DateTime.utc_now())
    notification = Repo.get_by!(AirUsageNotification, account_id: organization.account.id, user_id: admin.id)
    Accounts.update_user_role_in_organization(admin, organization, :user)

    reject(UserNotifier, :deliver_air_usage_notification, 3)
    assert :ok = perform_job(AirUsageNotificationWorker, %{notification_id: notification.id})
  end

  test "skips deleted notifications", %{notification: notification} do
    Repo.delete!(notification)
    reject(UserNotifier, :deliver_air_usage_notification, 3)
    assert :ok = perform_job(AirUsageNotificationWorker, %{notification_id: notification.id})
  end
end
