defmodule Tuist.Billing.Workers.ApplyStandingRunnerPrepaidWorker do
  @moduledoc """
  Grants an account its standing monthly prepaid minutes when a new
  billing period opens.

  Enqueued from the subscription webhook that reports the rollover, so
  the recurring case rides a signal Stripe already sends rather than a
  cron guessing at when each account's period turns over. Every account
  renews on its own date, and a sweep would have to re-derive all of
  them.

  Uniqueness is on the account and the period it is granting for, which
  catches a redelivery landing while the first job is still in the table.
  It is not what stops a period being granted twice: completed jobs are
  pruned within hours, and a stale subscription event followed by a newer
  one enqueues an already-granted period again. That guarantee is the
  granted period recorded on the account, which
  `Tuist.Runners.Prepaid.apply_standing_minutes/2` checks before granting
  and only moves forward after.

  Retrying is safe for the same reason it is needed. The charge is raised
  under a key stable for the account, period and level, so an attempt whose
  charge Stripe accepted but whose response was lost gets that charge back
  on the retry rather than raising a second one.
  """
  use Oban.Worker,
    max_attempts: 10,
    unique: [keys: [:account_id, :period_start], period: :infinity]

  alias Tuist.Accounts
  alias Tuist.Runners.Prepaid
  alias Tuist.Runners.Trials

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_id" => account_id, "period_start" => period_start}}) do
    {:ok, period_start, _offset} = DateTime.from_iso8601(period_start)

    case Accounts.get_account_by_id(account_id) do
      {:ok, account} -> apply_standing(account, period_start)
      {:error, :not_found} -> :ok
    end
  end

  # A trial is an account whose runner usage is not billed at all, so a
  # grant has nothing to draw against. Charging for one would take money
  # for credit that can never be spent, which is worse than the standing
  # order lapsing for as long as the trial runs.
  defp apply_standing(account, period_start) do
    if Trials.on_trial?(account) do
      Logger.info(
        "runners: account #{account.id} is on a runner trial, standing prepaid minutes not granted for #{period_start}"
      )

      :ok
    else
      account |> Prepaid.apply_standing_minutes(period_start) |> handle_result(account, period_start)
    end
  end

  defp handle_result({:ok, :no_standing_order}, _account, _period_start), do: :ok

  defp handle_result({:ok, :already_granted}, account, period_start) do
    Logger.info(
      "runners: account #{account.id} already holds its standing prepaid minutes for the period opening #{period_start}"
    )

    :ok
  end

  defp handle_result({:ok, _result}, account, period_start) do
    Logger.info(
      "runners: granted account #{account.id} its standing prepaid minutes " <>
        "(#{Prepaid.standing_minutes(account)}) for the period opening #{period_start}"
    )

    :ok
  end

  defp handle_result({:error, reason}, account, period_start) do
    Logger.warning(
      "runners: could not grant account #{account.id} its standing prepaid minutes " <>
        "for the period opening #{period_start}: #{inspect(reason)}"
    )

    {:error, reason}
  end
end
