defmodule Tuist.Billing.Workers.PaymentGraceExpirySweepWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import Ecto.Query, only: [from: 2]

  alias Tuist.Accounts
  alias Tuist.Billing.Subscription
  alias Tuist.Billing.Workers.PaymentGraceExpiredNotificationWorker
  alias Tuist.Billing.Workers.PaymentGraceExpirySweepWorker
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  setup do
    organization = AccountsFixtures.organization_fixture()
    admin = AccountsFixtures.user_fixture()
    member = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(admin, organization, role: :admin)
    Accounts.add_user_to_organization(member, organization, role: :user)

    %{account: organization.account, admin: admin, member: member}
  end

  test "queues the expiry email for the admins of an account past its grace period and marks it", %{
    account: account,
    admin: admin,
    member: member
  } do
    past_due_since = days_ago(8)
    subscription = past_due_subscription(account, past_due_since: past_due_since)

    assert :ok = perform_job(PaymentGraceExpirySweepWorker, %{})

    jobs = all_enqueued(worker: PaymentGraceExpiredNotificationWorker)
    user_ids = Enum.map(jobs, & &1.args["user_id"])
    grace_ends_at = past_due_since |> DateTime.add(7, :day) |> DateTime.to_iso8601()

    assert admin.id in user_ids
    refute member.id in user_ids
    assert Enum.all?(jobs, &(&1.args["subscription_id"] == subscription.id and &1.args["grace_ends_at"] == grace_ends_at))
    assert %DateTime{} = Repo.get!(Subscription, subscription.id).payment_grace_expiry_notified_at
  end

  # Oban prunes finished jobs within hours, so the marker is what keeps a
  # later sweep from announcing the same episode again.
  test "announces an episode once, even after its jobs were pruned", %{account: account} do
    past_due_subscription(account, past_due_since: days_ago(8))

    assert :ok = perform_job(PaymentGraceExpirySweepWorker, %{})
    assert [_ | _] = all_enqueued(worker: PaymentGraceExpiredNotificationWorker)
    Repo.delete_all(Oban.Job)

    assert :ok = perform_job(PaymentGraceExpirySweepWorker, %{})

    assert all_enqueued(worker: PaymentGraceExpiredNotificationWorker) == []
  end

  test "announces a later overdue episode of a subscription announced before", %{account: account} do
    past_due_subscription(account,
      past_due_since: days_ago(8),
      payment_grace_expiry_notified_at: days_ago(40)
    )

    assert :ok = perform_job(PaymentGraceExpirySweepWorker, %{})

    assert [_ | _] = all_enqueued(worker: PaymentGraceExpiredNotificationWorker)
  end

  test "leaves accounts still within their grace period alone", %{account: account} do
    subscription = past_due_subscription(account, past_due_since: days_ago(6))

    assert :ok = perform_job(PaymentGraceExpirySweepWorker, %{})

    assert all_enqueued(worker: PaymentGraceExpiredNotificationWorker) == []
    assert is_nil(Repo.get!(Subscription, subscription.id).payment_grace_expiry_notified_at)
  end

  test "leaves Air subscriptions alone", %{account: account} do
    past_due_subscription(account, plan: :air, past_due_since: days_ago(8))

    assert :ok = perform_job(PaymentGraceExpirySweepWorker, %{})

    assert all_enqueued(worker: PaymentGraceExpiredNotificationWorker) == []
  end

  test "leaves an account alone, unmarked, while another subscription carries the plan", %{account: account} do
    subscription = past_due_subscription(account, past_due_since: days_ago(8))
    BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro, status: "active")

    assert :ok = perform_job(PaymentGraceExpirySweepWorker, %{})

    assert all_enqueued(worker: PaymentGraceExpiredNotificationWorker) == []
    assert is_nil(Repo.get!(Subscription, subscription.id).payment_grace_expiry_notified_at)
  end

  test "announces the expiry once the other subscription stops carrying the plan", %{account: account} do
    past_due_subscription(account, past_due_since: days_ago(8))
    other = BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro, status: "active")
    assert :ok = perform_job(PaymentGraceExpirySweepWorker, %{})

    Repo.update_all(from(s in Subscription, where: s.id == ^other.id), set: [status: "canceled"])
    assert :ok = perform_job(PaymentGraceExpirySweepWorker, %{})

    assert [_ | _] = all_enqueued(worker: PaymentGraceExpiredNotificationWorker)
  end

  # A replica predating the anchor can write a past due row without one
  # during a rolling deploy. Its grace runs from `updated_at`, which the sweep
  # pins so a later write cannot move it.
  test "pins the anchor of a past due row written without one", %{account: account} do
    subscription = past_due_subscription(account, past_due_since: nil)
    updated_at = days_ago(8)

    Repo.update_all(from(s in Subscription, where: s.id == ^subscription.id),
      set: [updated_at: DateTime.to_naive(updated_at)]
    )

    assert :ok = perform_job(PaymentGraceExpirySweepWorker, %{})

    assert [_ | _] = all_enqueued(worker: PaymentGraceExpiredNotificationWorker)
    assert Repo.get!(Subscription, subscription.id).past_due_since == updated_at
  end

  defp days_ago(days), do: DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), -days, :day)

  defp past_due_subscription(account, opts) do
    BillingFixtures.subscription_fixture(Keyword.merge([account_id: account.id, plan: :pro, status: "past_due"], opts))
  end
end
