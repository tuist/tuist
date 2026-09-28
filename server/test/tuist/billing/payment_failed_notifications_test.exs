defmodule Tuist.Billing.PaymentFailedNotificationsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Billing.PaymentFailedNotifications
  alias Tuist.Billing.Workers.PaymentFailedNotificationWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures

  @failed_at ~U[2026-09-27 10:00:00Z]

  defp renewal_invoice(customer_id, overrides \\ %{}) do
    Map.merge(
      %Stripe.Invoice{
        id: "in_#{System.unique_integer([:positive])}",
        customer: customer_id,
        attempt_count: 1,
        billing_reason: "subscription_cycle",
        collection_method: "charge_automatically"
      },
      overrides
    )
  end

  defp organization_with_admins do
    organization = AccountsFixtures.organization_fixture(customer_id: "cus_#{System.unique_integer([:positive])}")
    admin = AccountsFixtures.user_fixture()
    member = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(admin, organization, role: :admin)
    Accounts.add_user_to_organization(member, organization, role: :user)
    %{organization: organization, admin: admin, member: member}
  end

  test "queues the email for every admin of the account, with the date its plan stays active until" do
    %{organization: organization, admin: admin, member: member} = organization_with_admins()
    invoice = renewal_invoice(organization.account.customer_id)

    PaymentFailedNotifications.enqueue(invoice, @failed_at)

    jobs = all_enqueued(worker: PaymentFailedNotificationWorker)
    user_ids = Enum.map(jobs, & &1.args["user_id"])

    assert admin.id in user_ids
    refute member.id in user_ids

    assert Enum.all?(jobs, fn job ->
             job.args["invoice_id"] == invoice.id and job.args["account_id"] == organization.account.id and
               job.args["plan_active_until"] == "2026-10-11T10:00:00Z"
           end)
  end

  test "queues the email for the owner of a personal account" do
    user = AccountsFixtures.user_fixture(customer_id: "cus_#{System.unique_integer([:positive])}", preload: [:account])

    PaymentFailedNotifications.enqueue(renewal_invoice(user.account.customer_id), @failed_at)

    assert [%{args: %{"user_id" => user_id}}] = all_enqueued(worker: PaymentFailedNotificationWorker)
    assert user_id == user.id
  end

  # Stripe sends `invoice.payment_failed` for every retry. Only the first one
  # starts the window the email promises, so later attempts send nothing.
  test "queues nothing for a retry of an invoice that already failed" do
    %{organization: organization} = organization_with_admins()

    PaymentFailedNotifications.enqueue(renewal_invoice(organization.account.customer_id, %{attempt_count: 2}), @failed_at)

    assert all_enqueued(worker: PaymentFailedNotificationWorker) == []
  end

  test "queues the email once when Stripe delivers the same failure twice" do
    %{organization: organization} = organization_with_admins()
    invoice = renewal_invoice(organization.account.customer_id)

    PaymentFailedNotifications.enqueue(invoice, @failed_at)
    PaymentFailedNotifications.enqueue(invoice, @failed_at)

    assert [_admin_job, _creator_job] = all_enqueued(worker: PaymentFailedNotificationWorker)
  end

  # An enterprise subscription is invoiced (`send_invoice`) and nothing is
  # charged automatically, and a one-off invoice has no plan to lose.
  test "queues nothing for invoices that are not an automatically charged subscription" do
    %{organization: organization} = organization_with_admins()
    customer_id = organization.account.customer_id

    PaymentFailedNotifications.enqueue(renewal_invoice(customer_id, %{collection_method: "send_invoice"}), @failed_at)
    PaymentFailedNotifications.enqueue(renewal_invoice(customer_id, %{billing_reason: "manual"}), @failed_at)

    assert all_enqueued(worker: PaymentFailedNotificationWorker) == []
  end

  test "queues nothing for a customer without an account" do
    PaymentFailedNotifications.enqueue(renewal_invoice("cus_unknown"), @failed_at)

    assert all_enqueued(worker: PaymentFailedNotificationWorker) == []
  end
end
