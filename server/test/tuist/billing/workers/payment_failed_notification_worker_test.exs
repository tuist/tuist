defmodule Tuist.Billing.Workers.PaymentFailedNotificationWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import Bamboo.Test

  alias Tuist.Accounts
  alias Tuist.Accounts.UserNotifier
  alias Tuist.Billing.Workers.PaymentFailedNotificationWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  setup do
    organization = AccountsFixtures.organization_fixture(name: "acme-#{System.unique_integer([:positive])}")
    admin = AccountsFixtures.user_fixture(email: "admin-#{System.unique_integer([:positive])}@tuist.dev")
    Accounts.add_user_to_organization(admin, organization, role: :admin)

    args = %{
      invoice_id: "in_open",
      account_id: organization.account.id,
      user_id: admin.id
    }

    %{account: organization.account, admin: admin, args: args}
  end

  test "emails the admin that the payment failed and where to pay", %{
    account: account,
    admin: admin,
    args: args
  } do
    stub(Stripe.Invoice, :retrieve, fn "in_open" -> {:ok, %Stripe.Invoice{id: "in_open", status: "open"}} end)

    assert :ok = perform_job(PaymentFailedNotificationWorker, args)

    assert_email_delivered_with(
      to: [nil: admin.email],
      subject: "A payment for the Tuist subscription of #{account.name} failed",
      text_body: ~r{The payment is retried automatically.*/#{account.name}/billing/pay}s
    )
  end

  test "states the deadline once the subscription is past due", %{account: account, admin: admin, args: args} do
    stub(Stripe.Invoice, :retrieve, fn "in_open" -> {:ok, %Stripe.Invoice{id: "in_open", status: "open"}} end)

    past_due_since = DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), -1, :day)

    BillingFixtures.subscription_fixture(
      account_id: account.id,
      plan: :pro,
      status: "past_due",
      past_due_since: past_due_since
    )

    assert :ok = perform_job(PaymentFailedNotificationWorker, args)

    deadline = past_due_since |> DateTime.add(7, :day) |> Timex.format!("{Mfull} {D}, {YYYY}, {h24}:{m} UTC")

    assert_email_delivered_with(
      to: [nil: admin.email],
      text_body: ~r{Your plan stays active until #{Regex.escape(deadline)}\.}
    )
  end

  # Stripe can report the failed invoice before the subscription change that
  # starts the grace period. The email then states the length, not a date.
  test "states the length of the grace period before the subscription is past due", %{admin: admin, args: args} do
    stub(Stripe.Invoice, :retrieve, fn "in_open" -> {:ok, %Stripe.Invoice{id: "in_open", status: "open"}} end)

    assert :ok = perform_job(PaymentFailedNotificationWorker, args)

    assert_email_delivered_with(
      to: [nil: admin.email],
      text_body: ~r{stays active for 7 days after the subscription is marked overdue.*billing page shows the exact date}s
    )
  end

  test "says the plan is already limited when an earlier failure used up the grace period", %{
    account: account,
    admin: admin,
    args: args
  } do
    stub(Stripe.Invoice, :retrieve, fn "in_open" -> {:ok, %Stripe.Invoice{id: "in_open", status: "open"}} end)

    BillingFixtures.subscription_fixture(
      account_id: account.id,
      plan: :pro,
      status: "past_due",
      past_due_since: DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), -8, :day)
    )

    assert :ok = perform_job(PaymentFailedNotificationWorker, args)

    assert_email_delivered_with(
      to: [nil: admin.email],
      text_body: ~r{already limited to the free tier of the Air plan.*restore your plan}s
    )
  end

  # Stripe keeps retrying past the grace period, so the email must not suggest
  # the plan lasts as long as the retries do.
  test "does not tie the plan to the retries", %{account: account, admin: admin} do
    email = UserNotifier.payment_failed_email(admin, account)

    refute email.text_body =~ ~r{while the payment is retried|when the retries end}i
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

    expect(UserNotifier, :deliver_payment_failed_notification, fn _user, _account, _grace ->
      {:error, :smtp_timeout}
    end)

    assert {:error, :smtp_timeout} = perform_job(PaymentFailedNotificationWorker, args)
  end
end
