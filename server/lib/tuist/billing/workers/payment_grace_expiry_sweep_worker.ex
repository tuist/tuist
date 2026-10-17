defmodule Tuist.Billing.Workers.PaymentGraceExpirySweepWorker do
  @moduledoc """
  Tells the admins of every paid account whose subscription stayed past due
  beyond the payment grace period that the account is now limited to Air.

  Nothing happens at the deadline itself: access is resolved at read time by
  `Subscription.entitled?/2`. This sweep only announces it, so it runs every
  fifteen minutes and answers for a bounded batch each time.

  `payment_grace_expiry_notified_at` is the durable marker. Oban prunes
  completed jobs within hours, so job uniqueness alone would announce an
  episode again. An episode counts as announced once the marker is no older
  than its anchor. A recovery clears both the anchor and the marker, so a
  later failure is announced again even within the same second. The marker and the delivery jobs are written in one transaction
  under the account's subscription lock, so they commit together and never
  race the subscription webhook. An account another subscription still
  carries the plan for is neither emailed nor marked.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [fields: [:worker], period: :infinity, states: :incomplete]

  import Ecto.Query

  alias Tuist.Accounts
  alias Tuist.Billing
  alias Tuist.Billing.PaymentFailedNotifications
  alias Tuist.Billing.Subscription
  alias Tuist.Repo

  @batch_size 500

  @impl Oban.Worker
  def perform(_job) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    now
    |> candidates()
    |> Enum.each(&announce(&1, now))

    :ok
  end

  # A processed candidate leaves the set because its marker is written. An
  # account another subscription still carries the plan for has lost
  # nothing, so it is left out here rather than marked: should that other
  # subscription end first, this one's expiry is still news.
  defp candidates(now) do
    cutoff = DateTime.add(now, -Subscription.payment_grace_period_days(), :day)
    entitled_account_ids = select(Billing.entitled_subscriptions_query(), [e], e.account_id)

    anchored =
      from(s in Subscription,
        where: s.status == "past_due" and s.plan != :air,
        where: s.past_due_since <= ^cutoff,
        where: is_nil(s.payment_grace_expiry_notified_at) or s.payment_grace_expiry_notified_at < s.past_due_since,
        where: s.account_id not in subquery(entitled_account_ids),
        order_by: [asc: s.past_due_since, asc: s.id],
        limit: @batch_size,
        select: {s.id, s.account_id}
      )

    # A replica that predates the anchor can still write a past due row
    # without one during a rolling deploy. Its grace runs from `updated_at`
    # (see `Subscription.payment_grace_ends_at/1`), and the sweep pins that
    # anchor so a later write cannot move it.
    unanchored =
      from(s in Subscription,
        where: s.status == "past_due" and s.plan != :air,
        where: is_nil(s.past_due_since) and s.updated_at <= ^DateTime.to_naive(cutoff),
        where: s.account_id not in subquery(entitled_account_ids),
        order_by: [asc: s.updated_at, asc: s.id],
        limit: @batch_size,
        select: {s.id, s.account_id}
      )

    Repo.all(anchored) ++ Repo.all(unanchored)
  end

  defp announce({subscription_id, account_id}, now) do
    {:ok, _result} =
      Billing.with_subscription_lock(account_id, fn ->
        # Read again under the lock: the webhook may have recovered or moved
        # the subscription, or another one may carry the plan now.
        with %Subscription{} = subscription <- Repo.get(Subscription, subscription_id),
             true <- unannounced_expiry?(subscription, now),
             {:ok, account} <- Accounts.get_account_by_id(account_id),
             true <- Billing.payment_failed?(account) do
          subscription = subscription |> pin_anchor() |> mark_announced(now)
          PaymentFailedNotifications.enqueue_payment_grace_expired(account, subscription)
        end

        :ok
      end)
  end

  defp unannounced_expiry?(%Subscription{status: "past_due", plan: plan} = subscription, now) when plan != :air do
    case Subscription.payment_grace_ends_at(subscription) do
      %DateTime{} = grace_ends_at ->
        not Subscription.entitled?(subscription, now) and not announced?(subscription, anchor(grace_ends_at))

      nil ->
        false
    end
  end

  defp unannounced_expiry?(_subscription, _now), do: false

  defp announced?(%Subscription{payment_grace_expiry_notified_at: %DateTime{} = notified_at}, anchor),
    do: not DateTime.before?(notified_at, anchor)

  defp announced?(_subscription, _anchor), do: false

  defp anchor(grace_ends_at), do: DateTime.add(grace_ends_at, -Subscription.payment_grace_period_days(), :day)

  defp pin_anchor(%Subscription{past_due_since: nil} = subscription) do
    anchor =
      subscription
      |> Subscription.payment_grace_ends_at()
      |> anchor()
      |> DateTime.truncate(:second)

    # `update_all` leaves `updated_at` alone, which is what the anchor was
    # read from.
    Repo.update_all(from(s in Subscription, where: s.id == ^subscription.id), set: [past_due_since: anchor])
    %{subscription | past_due_since: anchor}
  end

  defp pin_anchor(subscription), do: subscription

  defp mark_announced(subscription, now) do
    Repo.update_all(from(s in Subscription, where: s.id == ^subscription.id),
      set: [payment_grace_expiry_notified_at: now]
    )

    %{subscription | payment_grace_expiry_notified_at: now}
  end
end
