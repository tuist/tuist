defmodule Tuist.Billing.PaymentFailedNotificationsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import Ecto.Query, only: [from: 2]

  alias Tuist.Accounts
  alias Tuist.Billing.PaymentFailedNotifications
  alias Tuist.Billing.Subscription
  alias Tuist.Billing.Workers.PaymentFailedNotificationWorker
  alias Tuist.Billing.Workers.PaymentGraceExpiredNotificationWorker
  alias Tuist.Billing.Workers.PaymentGraceStartedNotificationWorker
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

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

  test "queues the email for every admin of the account" do
    %{organization: organization, admin: admin, member: member} = organization_with_admins()
    invoice = renewal_invoice(organization.account.customer_id)

    PaymentFailedNotifications.enqueue(invoice)

    jobs = all_enqueued(worker: PaymentFailedNotificationWorker)
    user_ids = Enum.map(jobs, & &1.args["user_id"])

    assert admin.id in user_ids
    refute member.id in user_ids

    assert Enum.all?(jobs, &(&1.args["invoice_id"] == invoice.id and &1.args["account_id"] == organization.account.id))
  end

  test "queues the email for the owner of a personal account" do
    user = AccountsFixtures.user_fixture(customer_id: "cus_#{System.unique_integer([:positive])}", preload: [:account])

    PaymentFailedNotifications.enqueue(renewal_invoice(user.account.customer_id))

    assert [%{args: %{"user_id" => user_id}}] = all_enqueued(worker: PaymentFailedNotificationWorker)
    assert user_id == user.id
  end

  # Stripe sends `invoice.payment_failed` for every retry. The email is about
  # the failure, not each attempt, so later attempts send nothing.
  test "queues nothing for a retry of an invoice that already failed" do
    %{organization: organization} = organization_with_admins()

    PaymentFailedNotifications.enqueue(renewal_invoice(organization.account.customer_id, %{attempt_count: 2}))

    assert all_enqueued(worker: PaymentFailedNotificationWorker) == []
  end

  test "queues the email once when Stripe delivers the same failure twice" do
    %{organization: organization} = organization_with_admins()
    invoice = renewal_invoice(organization.account.customer_id)

    PaymentFailedNotifications.enqueue(invoice)
    PaymentFailedNotifications.enqueue(invoice)

    assert [_admin_job, _creator_job] = all_enqueued(worker: PaymentFailedNotificationWorker)
  end

  # An enterprise subscription is invoiced (`send_invoice`) and nothing is
  # charged automatically, and a one-off invoice has no plan to lose.
  test "queues nothing for invoices that are not an automatically charged subscription" do
    %{organization: organization} = organization_with_admins()
    customer_id = organization.account.customer_id

    PaymentFailedNotifications.enqueue(renewal_invoice(customer_id, %{collection_method: "send_invoice"}))
    PaymentFailedNotifications.enqueue(renewal_invoice(customer_id, %{billing_reason: "manual"}))

    assert all_enqueued(worker: PaymentFailedNotificationWorker) == []
  end

  test "queues nothing for a customer without an account" do
    PaymentFailedNotifications.enqueue(renewal_invoice("cus_unknown"))

    assert all_enqueued(worker: PaymentFailedNotificationWorker) == []
  end

  describe "enqueue_payment_grace_started/2" do
    test "queues the email for every admin with the subscription's deadline" do
      %{organization: organization, admin: admin, member: member} = organization_with_admins()
      past_due_since = DateTime.add(now(), -1, :day)
      subscription = past_due_subscription(organization.account, past_due_since)

      assert :ok = PaymentFailedNotifications.enqueue_payment_grace_started(organization.account, subscription)

      jobs = all_enqueued(worker: PaymentGraceStartedNotificationWorker)
      user_ids = Enum.map(jobs, & &1.args["user_id"])
      grace_ends_at = DateTime.to_iso8601(DateTime.add(past_due_since, 7, :day))

      assert admin.id in user_ids
      refute member.id in user_ids

      assert Enum.all?(
               jobs,
               &(&1.args["subscription_id"] == subscription.id and &1.args["grace_ends_at"] == grace_ends_at and
                   &1.args["account_id"] == organization.account.id)
             )
    end

    test "marks the jobs as the policy notice when asked to" do
      %{organization: organization} = organization_with_admins()
      subscription = past_due_subscription(organization.account, DateTime.add(now(), -1, :day))

      PaymentFailedNotifications.enqueue_payment_grace_started(organization.account, subscription, notice: :policy)

      assert [_ | _] = jobs = all_enqueued(worker: PaymentGraceStartedNotificationWorker)
      assert Enum.all?(jobs, &(&1.args["notice"] == "policy"))
    end

    test "queues the email once when the transition is reported twice" do
      %{organization: organization} = organization_with_admins()
      subscription = past_due_subscription(organization.account, DateTime.add(now(), -1, :day))

      PaymentFailedNotifications.enqueue_payment_grace_started(organization.account, subscription)
      PaymentFailedNotifications.enqueue_payment_grace_started(organization.account, subscription)

      assert [_admin_job, _creator_job] = all_enqueued(worker: PaymentGraceStartedNotificationWorker)
    end

    # The expiry email tells the account it lost its plan; saying it still has
    # it until a date in the past would be wrong.
    test "queues nothing once the grace period is over" do
      %{organization: organization} = organization_with_admins()
      subscription = past_due_subscription(organization.account, DateTime.add(now(), -8, :day))

      PaymentFailedNotifications.enqueue_payment_grace_started(organization.account, subscription)

      assert all_enqueued(worker: PaymentGraceStartedNotificationWorker) == []
    end

    test "queues nothing for a subscription that is not past due" do
      %{organization: organization} = organization_with_admins()
      subscription = BillingFixtures.subscription_fixture(account_id: organization.account.id, status: "active")

      PaymentFailedNotifications.enqueue_payment_grace_started(organization.account, subscription)

      assert all_enqueued(worker: PaymentGraceStartedNotificationWorker) == []
    end
  end

  describe "enqueue_payment_grace_expired/2" do
    test "queues the email for every admin of the account" do
      %{organization: organization, admin: admin, member: member} = organization_with_admins()
      subscription = past_due_subscription(organization.account, DateTime.add(now(), -8, :day))

      PaymentFailedNotifications.enqueue_payment_grace_expired(organization.account, subscription)

      user_ids = Enum.map(all_enqueued(worker: PaymentGraceExpiredNotificationWorker), & &1.args["user_id"])
      assert admin.id in user_ids
      refute member.id in user_ids
    end
  end

  describe "grace_episode_subscription/3" do
    setup do
      %{organization: organization} = organization_with_admins()
      past_due_since = DateTime.add(now(), -1, :day)
      subscription = past_due_subscription(organization.account, past_due_since)
      grace_ends_at = DateTime.to_iso8601(DateTime.add(past_due_since, 7, :day))

      %{account: organization.account, subscription: subscription, grace_ends_at: grace_ends_at}
    end

    test "returns the subscription while it is the same overdue episode", %{
      account: account,
      subscription: subscription,
      grace_ends_at: grace_ends_at
    } do
      assert %Subscription{id: id} =
               PaymentFailedNotifications.grace_episode_subscription(subscription.id, account.id, grace_ends_at)

      assert id == subscription.id
    end

    test "returns nil once the subscription recovered", %{
      account: account,
      subscription: subscription,
      grace_ends_at: grace_ends_at
    } do
      update_subscription(subscription, status: "active", past_due_since: nil)

      assert PaymentFailedNotifications.grace_episode_subscription(subscription.id, account.id, grace_ends_at) == nil
    end

    test "returns nil for a later overdue episode", %{
      account: account,
      subscription: subscription,
      grace_ends_at: grace_ends_at
    } do
      update_subscription(subscription, past_due_since: now())

      assert PaymentFailedNotifications.grace_episode_subscription(subscription.id, account.id, grace_ends_at) == nil
    end

    test "returns nil for a subscription of another account", %{subscription: subscription, grace_ends_at: grace_ends_at} do
      other = AccountsFixtures.organization_fixture()

      assert PaymentFailedNotifications.grace_episode_subscription(subscription.id, other.account.id, grace_ends_at) ==
               nil
    end
  end

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)

  defp past_due_subscription(account, past_due_since) do
    BillingFixtures.subscription_fixture(
      account_id: account.id,
      plan: :pro,
      status: "past_due",
      past_due_since: past_due_since
    )
  end

  defp update_subscription(subscription, changes) do
    Repo.update_all(from(s in Subscription, where: s.id == ^subscription.id), set: changes)
  end
end
