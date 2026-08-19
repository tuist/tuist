defmodule Tuist.Runners.Trials do
  @moduledoc """
  Runner trials: an account that uses runners without being billed for
  them, until someone deliberately ends it.

  ## What a trial is

  A trial is the absence of a runner item on the account's Stripe
  subscription. Usage is still metered and still reported gross, exactly
  as it is for everyone else, but with no subscription item carrying a
  runner Price there is nothing for Stripe to invoice it against. That
  is the same guarantee the whole runner rollout has been resting on
  since the meters went in, made explicit and per-account.

  Deliberately *not* a credit grant. A grant is a finite pot of money
  that runs out, so it can neither run open-ended until cancelled nor
  promise that nothing runner-related is billed. And deliberately not a
  suppression of meter reporting either: reporting stays identical for
  every account, trial or not, which is the invariant that lets the
  metering path stay ignorant of commercial arrangements.

  ## Ending one

  Ending a trial adds the runner items to the account's live
  subscription, which is what makes its usage billable from then on.
  An account with no subscription simply has the trial cleared; it will
  pick the items up whenever it next gets one.

  Whether Stripe bills meter events recorded *before* the item was added
  is not something we have confirmed. Until it is, treat ending a trial
  mid-period as capable of billing that period's earlier usage, and
  prefer ending one at a period boundary.
  """

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Billing
  alias Tuist.Repo
  alias Tuist.Runners.RunnerSession

  @doc """
  True when `account` is on a runner trial, and so must not carry a
  runner subscription item.
  """
  def on_trial?(%Account{runner_trial_started_at: nil}), do: false
  def on_trial?(%Account{runner_trial_ended_at: nil}), do: true
  def on_trial?(_account), do: false

  @doc """
  Puts `account` on a runner trial, open-ended until `cancel/1`.

  Restarting a trial for an account whose previous one was cancelled is
  allowed: the new start replaces both timestamps, so the account reads
  as on trial again.
  """
  def start(%Account{} = account) do
    with {:ok, account} <-
           account
           |> Account.runner_trial_changeset(%{
             runner_trial_started_at: DateTime.utc_now(),
             runner_trial_ended_at: nil
           })
           |> Repo.update(),
         {:ok, _} <- Billing.sync_runner_subscription_items(account) do
      {:ok, account}
    end
  end

  @doc """
  Ends `account`'s runner trial, making its runner usage billable.

  Returns `{:ok, account}` having stamped the end, or `{:error, reason}`
  if the account was not on a trial.
  """
  def cancel(%Account{} = account) do
    if on_trial?(account) do
      with {:ok, account} <-
             account
             |> Account.runner_trial_changeset(%{runner_trial_ended_at: DateTime.utc_now()})
             |> Repo.update(),
           {:ok, _} <- Billing.sync_runner_subscription_items(account) do
        {:ok, account}
      end
    else
      {:error, :not_on_trial}
    end
  end

  @doc """
  Puts every account that has already run a runner job onto a trial,
  and reports how many it started.

  A migration does this once when runner trials ship, but the runner
  Price is wired up later and separately. Any account that starts using
  runners in between would otherwise miss the trial and be billed the
  moment the Price lands, so this is re-runnable: run it immediately
  before wiring a Price in an environment.

  Idempotent. It only touches accounts with no trial recorded at all,
  so it can never restart one that was deliberately cancelled.

  Does not reconcile subscriptions, because an account it touches has no
  runner item to remove: it is on trial precisely because nothing has
  made its usage billable yet.
  """
  def backfill_current_runner_users do
    {count, _} =
      Repo.update_all(
        from(a in Account,
          where: is_nil(a.runner_trial_started_at) and is_nil(a.runner_trial_ended_at),
          where: a.id in subquery(from(s in RunnerSession, select: s.account_id, distinct: true))
        ),
        set: [runner_trial_started_at: DateTime.utc_now()]
      )

    count
  end

  @doc """
  Accounts currently on a runner trial.
  """
  def list_accounts_on_trial do
    Repo.all(
      from(a in Account,
        where: not is_nil(a.runner_trial_started_at) and is_nil(a.runner_trial_ended_at)
      )
    )
  end
end
