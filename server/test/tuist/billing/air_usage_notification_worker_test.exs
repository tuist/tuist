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
    user = AccountsFixtures.user_fixture()
    set_cache_requests(user.account.id, 800_000)
    {:ok, _} = AirUsageNotifications.enqueue(user.account.id, DateTime.utc_now())
    notification = Repo.get_by!(AirUsageNotification, account_id: user.account.id)
    %{user: user, notification: notification}
  end

  test "records success and does not redeliver a completed notification", %{user: user, notification: notification} do
    expect(UserNotifier, :deliver_air_usage_notification, fn recipient, account, delivered ->
      refute Repo.in_transaction?()
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
    Accounts.update_account_current_month_usage(user.account.id, %{cache_requests: 1_000_000})
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
    organization = AccountsFixtures.organization_fixture()
    set_cache_requests(organization.account.id, 800_000)
    admin = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(admin, organization, role: :admin)
    {:ok, _} = AirUsageNotifications.enqueue(organization.account.id, DateTime.utc_now())
    notification = Repo.get_by!(AirUsageNotification, account_id: organization.account.id, user_id: admin.id)
    Accounts.update_user_role_in_organization(admin, organization, :user)

    reject(UserNotifier, :deliver_air_usage_notification, 3)
    assert :ok = perform_job(AirUsageNotificationWorker, %{notification_id: notification.id})
  end

  test "never delivers a stored remote cache hits notification", %{notification: notification} do
    notification |> change(metric: :remote_cache_hits) |> Repo.update!()
    reject(UserNotifier, :deliver_air_usage_notification, 3)
    assert :ok = perform_job(AirUsageNotificationWorker, %{notification_id: notification.id})
    refute Repo.reload!(notification).delivered_at
  end

  test "skips deleted notifications", %{notification: notification} do
    Repo.delete!(notification)
    reject(UserNotifier, :deliver_air_usage_notification, 3)
    assert :ok = perform_job(AirUsageNotificationWorker, %{notification_id: notification.id})
  end

  test "renders and persists the current usage rather than the enqueue snapshot", %{
    user: user,
    notification: notification
  } do
    Accounts.update_account_current_month_usage(user.account.id, %{cache_requests: 950_000})

    expect(UserNotifier, :deliver_air_usage_notification, fn _, _, delivered ->
      assert delivered.usage == 950_000
      assert delivered.limit == 1_000_000
      {:ok, :email}
    end)

    assert :ok = perform_job(AirUsageNotificationWorker, %{notification_id: notification.id})
    assert %{usage: 950_000, delivered_at: %DateTime{}} = Repo.reload!(notification)
  end

  test "requeues a suppressed warning when an upgraded account returns to Air", %{user: user, notification: notification} do
    subscription = BillingFixtures.subscription_fixture(account_id: user.account.id, plan: :pro)
    stub(UserNotifier, :deliver_air_usage_notification, fn _, _, _ -> flunk("suppressed notification was delivered") end)
    assert :ok = perform_job(AirUsageNotificationWorker, %{notification_id: notification.id})
    complete_job(notification)
    refute Repo.reload!(notification).delivered_at

    subscription |> change(status: "canceled") |> Repo.update!()
    assert {:ok, _} = AirUsageNotifications.enqueue(user.account.id, DateTime.utc_now())
    assert_enqueued(worker: AirUsageNotificationWorker, args: %{notification_id: notification.id})
    expect(UserNotifier, :deliver_air_usage_notification, fn _, _, _ -> {:ok, :email} end)
    assert :ok = perform_job(AirUsageNotificationWorker, %{notification_id: notification.id})
    assert Repo.reload!(notification).delivered_at
  end

  test "requeues for an admin promoted again after suppression" do
    organization = AccountsFixtures.organization_fixture()
    set_cache_requests(organization.account.id, 800_000)
    admin = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(admin, organization, role: :admin)
    {:ok, _} = AirUsageNotifications.enqueue(organization.account.id, DateTime.utc_now())
    notification = Repo.get_by!(AirUsageNotification, account_id: organization.account.id, user_id: admin.id)
    Accounts.update_user_role_in_organization(admin, organization, :user)
    stub(UserNotifier, :deliver_air_usage_notification, fn _, _, _ -> flunk("suppressed notification was delivered") end)
    assert :ok = perform_job(AirUsageNotificationWorker, %{notification_id: notification.id})
    complete_job(notification)

    Accounts.update_user_role_in_organization(admin, organization, :admin)
    assert {:ok, _} = AirUsageNotifications.enqueue(organization.account.id, DateTime.utc_now())
    assert_enqueued(worker: AirUsageNotificationWorker, args: %{notification_id: notification.id})

    expect(UserNotifier, :deliver_air_usage_notification, fn recipient, _, _ ->
      assert recipient.id == admin.id
      {:ok, :email}
    end)

    assert :ok = perform_job(AirUsageNotificationWorker, %{notification_id: notification.id})
    assert Repo.reload!(notification).delivered_at
  end

  defp set_cache_requests(account_id, requests) do
    Accounts.update_account_current_month_usage(account_id, %{cache_requests: requests})
  end

  defp complete_job(notification) do
    Repo.update_all(from(j in Oban.Job, where: j.args == ^%{"notification_id" => notification.id}),
      set: [state: "completed"]
    )
  end
end
