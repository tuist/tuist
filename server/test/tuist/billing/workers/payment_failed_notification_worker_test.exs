defmodule Tuist.Billing.Workers.PaymentFailedNotificationWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import Bamboo.Test

  alias Tuist.Accounts
  alias Tuist.Accounts.UserNotifier
  alias Tuist.Billing.Workers.PaymentFailedNotificationWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    organization = AccountsFixtures.organization_fixture(name: "acme-#{System.unique_integer([:positive])}")
    admin = AccountsFixtures.user_fixture(email: "admin-#{System.unique_integer([:positive])}@tuist.dev")
    Accounts.add_user_to_organization(admin, organization, role: :admin)

    args = %{
      invoice_id: "in_open",
      account_id: organization.account.id,
      user_id: admin.id,
      plan_active_until: "2026-10-11T10:00:00Z"
    }

    %{account: organization.account, admin: admin, args: args}
  end

  test "emails the admin the date the plan stays active until and where to pay", %{
    account: account,
    admin: admin,
    args: args
  } do
    stub(Stripe.Invoice, :retrieve, fn "in_open" -> {:ok, %Stripe.Invoice{id: "in_open", status: "open"}} end)

    assert :ok = perform_job(PaymentFailedNotificationWorker, args)

    assert_email_delivered_with(
      to: [nil: admin.email],
      subject: "A payment for the Tuist subscription of #{account.name} failed",
      text_body: ~r{stays active until October 11, 2026 \(UTC\).*/#{account.name}/billing/pay}s
    )
  end

  test "sends nothing once the invoice was paid", %{args: args} do
    stub(Stripe.Invoice, :retrieve, fn "in_open" -> {:ok, %Stripe.Invoice{id: "in_open", status: "paid"}} end)
    reject(UserNotifier, :deliver_payment_failed_notification, 3)

    assert :ok = perform_job(PaymentFailedNotificationWorker, args)
  end

  test "sends nothing to a user who is no longer an admin", %{account: account, args: args} do
    stub(Stripe.Invoice, :retrieve, fn "in_open" -> {:ok, %Stripe.Invoice{id: "in_open", status: "open"}} end)
    reject(UserNotifier, :deliver_payment_failed_notification, 3)
    outsider = AccountsFixtures.user_fixture()

    assert :ok = perform_job(PaymentFailedNotificationWorker, %{args | user_id: outsider.id, account_id: account.id})
  end

  test "returns delivery failures to Oban so the email is retried", %{args: args} do
    stub(Stripe.Invoice, :retrieve, fn "in_open" -> {:ok, %Stripe.Invoice{id: "in_open", status: "open"}} end)
    expect(UserNotifier, :deliver_payment_failed_notification, fn _user, _account, _until -> {:error, :smtp_timeout} end)

    assert {:error, :smtp_timeout} = perform_job(PaymentFailedNotificationWorker, args)
  end
end
