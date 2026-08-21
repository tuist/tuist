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

  What happens to usage already metered earlier in the period depends on
  the subscription's `billing_mode`, which we never set, so it is
  whatever each subscription was created with and can differ per
  account. On `classic`, adding a meter-priced item mid-cycle bills only
  the usage recorded from the date the item was added, so the backlog is
  not charged. On `flexible`, Stripe prices usage at whatever price was
  in effect when the usage happened, and the documentation covers
  changing an item's price rather than adding an item that did not exist,
  so it does not say what happens when no price was in effect at all.

  Read the account's `billing_mode` before ending a trial mid-period.
  Ending one at a period boundary avoids the question entirely.

  https://docs.stripe.com/billing/subscriptions/usage-based/manage-billing-setup
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
  Puts every account that can use runners onto a trial, and reports how
  many it started.

  "Can use" is the `:runners` flag, not past usage. An account holding
  the flag that has not run a job yet is exactly the one a usage-only
  backfill misses, and it would be billed for its very first job the
  moment a Price is wired up. Accounts that have already run something
  are included too, since the flag is only required in canary and
  production and an environment that does not require it has no gates to
  read.

  A migration does this once when runner trials ship, but the runner
  Price is wired up later and separately. Any account that gains access
  in between would otherwise miss the trial, so this is re-runnable: run
  it immediately before wiring a Price in an environment.

  Idempotent. It only touches accounts with no trial recorded at all,
  so it can never restart one that was deliberately cancelled.

  Does not reconcile subscriptions, because an account it touches has no
  runner item to remove: it is on trial precisely because nothing has
  made its usage billable yet.
  """
  def backfill_runner_trials do
    ran_a_job = from(s in RunnerSession, select: s.account_id, distinct: true)

    {count, _} =
      Repo.update_all(
        from(a in Account,
          where: is_nil(a.runner_trial_started_at) and is_nil(a.runner_trial_ended_at),
          where: a.id in subquery(ran_a_job) or a.id in ^accounts_with_runner_access()
        ),
        set: [runner_trial_started_at: DateTime.utc_now()]
      )

    count
  end

  # Accounts the `:runners` flag is switched on for, read from its actor
  # gates. A gate that is explicitly off is not access, and group and
  # boolean gates are deliberately ignored: neither names an account, so
  # neither can be turned into a list of accounts to put on trial.
  defp accounts_with_runner_access do
    case FunWithFlags.get_flag(:runners) do
      %FunWithFlags.Flag{gates: gates} ->
        gates
        |> Enum.filter(&(&1.type == :actor and &1.enabled))
        |> Enum.flat_map(fn gate ->
          case gate.for do
            "account:" <> id -> List.wrap(parse_id(id))
            _ -> []
          end
        end)

      _ ->
        []
    end
  end

  defp parse_id(id) do
    case Integer.parse(id) do
      {id, ""} -> id
      _ -> nil
    end
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
