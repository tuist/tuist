defmodule Tuist.Billing.Workers.PaymentGraceStartedNotificationWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import Bamboo.Test
  import Ecto.Query, only: [from: 2]

  alias Tuist.Accounts
  alias Tuist.Accounts.UserNotifier
  alias Tuist.Billing.Subscription
  alias Tuist.Billing.Workers.PaymentGraceStartedNotificationWorker
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  setup do
    organization = AccountsFixtures.organization_fixture(name: "acme-#{System.unique_integer([:positive])}")
    admin = AccountsFixtures.user_fixture(email: "admin-#{System.unique_integer([:positive])}@tuist.dev")
    Accounts.add_user_to_organization(admin, organization, role: :admin)

    subscription = overdue_subscription(organization.account, days_ago(1))

    %{
      account: organization.account,
      admin: admin,
      subscription: subscription,
      args: args(organization.account, admin, subscription)
    }
  end

  test "emails the admin that the invoice is overdue and until when the plan is kept", %{
    account: account,
    admin: admin,
    subscription: subscription,
    args: args
  } do
    assert :ok = perform_job(PaymentGraceStartedNotificationWorker, args)

    assert_email_delivered_with(
      to: [nil: admin.email],
      subject: "The Tuist subscription invoice of #{account.name} is overdue",
      text_body: ~r{stays active until #{Regex.escape(deadline(subscription))}.*/#{account.name}/billing/pay}s
    )
  end

  test "sends nothing once the invoice was paid", %{subscription: subscription, args: args} do
    update_subscription(subscription, status: "active", past_due_since: nil)
    reject(UserNotifier, :deliver_payment_grace_started_notification, 3)

    assert :ok = perform_job(PaymentGraceStartedNotificationWorker, args)
  end

  test "sends nothing once Stripe marked the subscription unpaid", %{subscription: subscription, args: args} do
    update_subscription(subscription, status: "unpaid")
    reject(UserNotifier, :deliver_payment_grace_started_notification, 3)

    assert :ok = perform_job(PaymentGraceStartedNotificationWorker, args)
  end

  test "sends nothing once the grace period is over", %{account: account, admin: admin} do
    subscription = overdue_subscription(account, days_ago(8))
    reject(UserNotifier, :deliver_payment_grace_started_notification, 3)

    assert :ok = perform_job(PaymentGraceStartedNotificationWorker, args(account, admin, subscription))
  end

  test "sends nothing for an earlier overdue episode", %{subscription: subscription, args: args} do
    update_subscription(subscription, past_due_since: days_ago(0))
    reject(UserNotifier, :deliver_payment_grace_started_notification, 3)

    assert :ok = perform_job(PaymentGraceStartedNotificationWorker, args)
  end

  test "sends nothing to a user who is no longer an admin", %{args: args} do
    reject(UserNotifier, :deliver_payment_grace_started_notification, 3)
    outsider = AccountsFixtures.user_fixture()

    assert :ok = perform_job(PaymentGraceStartedNotificationWorker, %{args | user_id: outsider.id})
  end

  test "returns delivery failures to Oban so the email is retried", %{args: args} do
    expect(UserNotifier, :deliver_payment_grace_started_notification, fn _user, _account, _deadline ->
      {:error, :smtp_timeout}
    end)

    assert {:error, :smtp_timeout} = perform_job(PaymentGraceStartedNotificationWorker, args)
  end

  describe "a job without a user" do
    test "queues the policy notice for every current admin with the current deadline", %{
      account: account,
      admin: admin,
      subscription: subscription
    } do
      assert :ok =
               perform_job(PaymentGraceStartedNotificationWorker, %{subscription_id: subscription.id, notice: "policy"})

      jobs = all_enqueued(worker: PaymentGraceStartedNotificationWorker)
      user_ids = Enum.map(jobs, & &1.args["user_id"])

      assert admin.id in user_ids

      assert Enum.all?(
               jobs,
               &(&1.args == %{
                   "account_id" => account.id,
                   "user_id" => &1.args["user_id"],
                   "subscription_id" => subscription.id,
                   "grace_ends_at" => args(account, admin, subscription).grace_ends_at,
                   "notice" => "policy"
                 })
             )
    end

    test "queues nothing once the subscription is no longer past due", %{subscription: subscription} do
      update_subscription(subscription, status: "active", past_due_since: nil)

      assert :ok =
               perform_job(PaymentGraceStartedNotificationWorker, %{subscription_id: subscription.id, notice: "policy"})

      assert all_enqueued(worker: PaymentGraceStartedNotificationWorker) == []
    end

    test "queues nothing for a subscription that no longer exists" do
      assert :ok = perform_job(PaymentGraceStartedNotificationWorker, %{subscription_id: -1, notice: "policy"})

      assert all_enqueued(worker: PaymentGraceStartedNotificationWorker) == []
    end
  end

  test "sends the policy notice when the job carries it", %{
    account: account,
    admin: admin,
    subscription: subscription,
    args: args
  } do
    assert :ok = perform_job(PaymentGraceStartedNotificationWorker, Map.put(args, :notice, "policy"))

    assert_email_delivered_with(
      to: [nil: admin.email],
      subject: "The Tuist subscription payment of #{account.name} is overdue",
      text_body:
        ~r{for as long as an overdue payment was retried.*stays active until #{Regex.escape(deadline(subscription))}}s
    )
  end

  defp days_ago(days), do: DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), -days, :day)

  defp overdue_subscription(account, past_due_since) do
    BillingFixtures.subscription_fixture(
      account_id: account.id,
      plan: :enterprise,
      status: "past_due",
      past_due_since: past_due_since
    )
  end

  defp args(account, admin, subscription) do
    %{
      account_id: account.id,
      user_id: admin.id,
      subscription_id: subscription.id,
      grace_ends_at: subscription.past_due_since |> DateTime.add(7, :day) |> DateTime.to_iso8601()
    }
  end

  defp deadline(subscription) do
    subscription.past_due_since |> DateTime.add(7, :day) |> Timex.format!("{Mfull} {D}, {YYYY}, {h24}:{m} UTC")
  end

  defp update_subscription(subscription, changes) do
    Repo.update_all(from(s in Subscription, where: s.id == ^subscription.id), set: changes)
  end
end
