defmodule Tuist.Billing.Workers.PaymentGraceExpiredNotificationWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import Bamboo.Test
  import Ecto.Query, only: [from: 2]

  alias Tuist.Accounts
  alias Tuist.Accounts.UserNotifier
  alias Tuist.Billing.Subscription
  alias Tuist.Billing.Workers.PaymentGraceExpiredNotificationWorker
  alias Tuist.Billing.Workers.PaymentGraceExpirySweepWorker
  alias Tuist.Billing.Workers.SubscriptionUnpaidNotificationWorker
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  setup do
    organization = AccountsFixtures.organization_fixture(name: "acme-#{System.unique_integer([:positive])}")
    admin = AccountsFixtures.user_fixture(email: "admin-#{System.unique_integer([:positive])}@tuist.dev")
    Accounts.add_user_to_organization(admin, organization, role: :admin)
    past_due_since = DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), -8, :day)

    subscription =
      BillingFixtures.subscription_fixture(
        account_id: organization.account.id,
        plan: :pro,
        status: "past_due",
        past_due_since: past_due_since
      )

    args = %{
      account_id: organization.account.id,
      user_id: admin.id,
      subscription_id: subscription.id,
      grace_ends_at: past_due_since |> DateTime.add(7, :day) |> DateTime.to_iso8601()
    }

    %{account: organization.account, admin: admin, subscription: subscription, args: args}
  end

  test "emails the admin that the account is limited to Air and where to pay", %{
    account: account,
    admin: admin,
    args: args
  } do
    assert :ok = perform_job(PaymentGraceExpiredNotificationWorker, args)

    assert_email_delivered_with(
      to: [nil: admin.email],
      subject: "#{account.name} is limited to the Air plan until its overdue invoice is paid",
      text_body: ~r{7-day grace period has ended.*/#{account.name}/billing/pay}s
    )
  end

  test "sends nothing once the invoice was paid", %{subscription: subscription, args: args} do
    update_subscription(subscription, status: "active", past_due_since: nil)
    reject(UserNotifier, :deliver_payment_grace_expired_notification, 2)

    assert :ok = perform_job(PaymentGraceExpiredNotificationWorker, args)
  end

  # The sweep marks the episode when it queues this email, and the unpaid
  # email defers to that marker. Stripe giving up before delivery must not
  # leave the account told by neither.
  test "still emails when Stripe marks the subscription unpaid before delivery", %{
    account: account,
    admin: admin,
    subscription: subscription
  } do
    assert :ok = perform_job(PaymentGraceExpirySweepWorker, %{})

    [job] =
      Enum.filter(all_enqueued(worker: PaymentGraceExpiredNotificationWorker), &(&1.args["user_id"] == admin.id))

    update_subscription(subscription, status: "unpaid")

    assert :ok = perform_job(PaymentGraceExpiredNotificationWorker, job.args)

    assert_email_delivered_with(
      to: [nil: admin.email],
      subject: "#{account.name} is limited to the Air plan until its overdue invoice is paid"
    )

    reject(UserNotifier, :deliver_subscription_unpaid_notification, 2)

    assert :ok =
             perform_job(SubscriptionUnpaidNotificationWorker, %{account_id: account.id, user_id: admin.id})
  end

  test "sends nothing once an unpaid subscription recovered", %{subscription: subscription, args: args} do
    assert :ok = perform_job(PaymentGraceExpirySweepWorker, %{})
    update_subscription(subscription, status: "active", past_due_since: nil, payment_grace_expiry_notified_at: nil)
    reject(UserNotifier, :deliver_payment_grace_expired_notification, 2)

    assert :ok = perform_job(PaymentGraceExpiredNotificationWorker, args)
  end

  test "sends nothing while another subscription carries the plan", %{account: account, args: args} do
    BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro, status: "active")
    reject(UserNotifier, :deliver_payment_grace_expired_notification, 2)

    assert :ok = perform_job(PaymentGraceExpiredNotificationWorker, args)
  end

  test "sends nothing for an earlier overdue episode", %{subscription: subscription, args: args} do
    update_subscription(subscription,
      past_due_since: DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), -9, :day)
    )

    reject(UserNotifier, :deliver_payment_grace_expired_notification, 2)

    assert :ok = perform_job(PaymentGraceExpiredNotificationWorker, args)
  end

  test "sends nothing to a user who is no longer an admin", %{args: args} do
    reject(UserNotifier, :deliver_payment_grace_expired_notification, 2)
    outsider = AccountsFixtures.user_fixture()

    assert :ok = perform_job(PaymentGraceExpiredNotificationWorker, %{args | user_id: outsider.id})
  end

  test "returns delivery failures to Oban so the email is retried", %{args: args} do
    expect(UserNotifier, :deliver_payment_grace_expired_notification, fn _user, _account -> {:error, :smtp_timeout} end)

    assert {:error, :smtp_timeout} = perform_job(PaymentGraceExpiredNotificationWorker, args)
  end

  defp update_subscription(subscription, changes) do
    Repo.update_all(from(s in Subscription, where: s.id == ^subscription.id), set: changes)
  end
end
