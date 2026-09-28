defmodule Tuist.Billing.Workers.SubscriptionUnpaidNotificationWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import Bamboo.Test

  alias Tuist.Accounts
  alias Tuist.Accounts.UserNotifier
  alias Tuist.Billing.Workers.SubscriptionUnpaidNotificationWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  setup do
    organization = AccountsFixtures.organization_fixture(name: "acme-#{System.unique_integer([:positive])}")
    admin = AccountsFixtures.user_fixture(email: "admin-#{System.unique_integer([:positive])}@tuist.dev")
    Accounts.add_user_to_organization(admin, organization, role: :admin)
    BillingFixtures.subscription_fixture(account_id: organization.account.id, plan: :pro, status: "unpaid")

    %{account: organization.account, admin: admin, args: %{account_id: organization.account.id, user_id: admin.id}}
  end

  test "emails the admin that the account moved to Air and where to pay", %{account: account, admin: admin, args: args} do
    assert :ok = perform_job(SubscriptionUnpaidNotificationWorker, args)

    assert_email_delivered_with(
      to: [nil: admin.email],
      subject: "#{account.name} moved to the Air plan because its subscription payment failed",
      text_body: ~r{free tier of the Air plan.*/#{account.name}/billing/pay}s
    )
  end

  test "sends nothing once the invoice was paid", %{account: account, args: args} do
    BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro, status: "active")
    reject(UserNotifier, :deliver_subscription_unpaid_notification, 2)

    assert :ok = perform_job(SubscriptionUnpaidNotificationWorker, args)
  end

  test "sends nothing to a user who is no longer an admin", %{args: args} do
    reject(UserNotifier, :deliver_subscription_unpaid_notification, 2)
    outsider = AccountsFixtures.user_fixture()

    assert :ok = perform_job(SubscriptionUnpaidNotificationWorker, %{args | user_id: outsider.id})
  end

  test "returns delivery failures to Oban so the email is retried", %{args: args} do
    expect(UserNotifier, :deliver_subscription_unpaid_notification, fn _user, _account -> {:error, :smtp_timeout} end)

    assert {:error, :smtp_timeout} = perform_job(SubscriptionUnpaidNotificationWorker, args)
  end
end
