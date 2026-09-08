defmodule Tuist.Billing.Workers.RefreshSubscriptionPeriodsWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Billing.Workers.RefreshSubscriptionPeriodsWorker
  alias Tuist.Billing.Workers.RefreshSubscriptionPeriodWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  defp subscription(subscription_id, opts \\ []) do
    BillingFixtures.subscription_fixture(
      [
        account_id: AccountsFixtures.organization_fixture(preload: [:account]).account.id,
        subscription_id: subscription_id
      ] ++ opts
    )
  end

  test "enqueues a refresh for every subscription whose period is stale" do
    # Given
    now = DateTime.utc_now()

    subscription("sub_stale")

    subscription("sub_running",
      current_period_start: DateTime.truncate(DateTime.shift(now, day: -1), :second),
      current_period_end: DateTime.truncate(DateTime.shift(now, month: 1), :second)
    )

    # When
    assert :ok == RefreshSubscriptionPeriodsWorker.perform(%Oban.Job{args: %{}})

    # Then
    assert_enqueued(worker: RefreshSubscriptionPeriodWorker, args: %{subscription_id: "sub_stale"})

    assert [job] = all_enqueued(worker: RefreshSubscriptionPeriodWorker)
    assert job.args["subscription_id"] == "sub_stale"
  end

  test "does not queue a subscription that is already waiting on a refresh" do
    # Given
    subscription("sub_stale")

    # A sweep while Stripe is down leaves the job retrying, and the next
    # sweep still sees the row as stale because nothing was written.
    assert :ok == RefreshSubscriptionPeriodsWorker.perform(%Oban.Job{args: %{}})

    # When
    assert :ok == RefreshSubscriptionPeriodsWorker.perform(%Oban.Job{args: %{}})

    # Then
    assert [_only_one] = all_enqueued(worker: RefreshSubscriptionPeriodWorker)
  end

  test "enqueues nothing once every row holds the period that is running" do
    # Given
    now = DateTime.utc_now()

    subscription("sub_running",
      current_period_start: DateTime.truncate(DateTime.shift(now, day: -1), :second),
      current_period_end: DateTime.truncate(DateTime.shift(now, month: 1), :second)
    )

    # When
    assert :ok == RefreshSubscriptionPeriodsWorker.perform(%Oban.Job{args: %{}})

    # Then
    # Steady state is a single indexed read and no Stripe traffic at all.
    assert [] == all_enqueued(worker: RefreshSubscriptionPeriodWorker)
  end
end
