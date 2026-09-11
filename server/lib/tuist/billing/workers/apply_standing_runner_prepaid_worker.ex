defmodule Tuist.Billing.Workers.ApplyStandingRunnerPrepaidWorker do
  @moduledoc """
  Grants an account its standing monthly prepaid minutes when a new
  billing period opens.

  Enqueued from the subscription webhook that reports the rollover, so
  the recurring case rides a signal Stripe already sends rather than a
  cron guessing at when each account's period turns over. Every account
  renews on its own date, and a sweep would have to re-derive all of
  them.

  Uniqueness is on the account and the period it is granting for. It
  catches a redelivery that lands while the first job is still in the
  table, which is the common case, but it is not the durable guard:
  completed jobs are pruned within hours and a key that no longer exists
  recognises nothing. What holds indefinitely is the caller only
  enqueuing when the recorded period moves forward.

  Granting twice for one period is survivable in any case, because
  setting replaces: the second grant withdraws the first and the charge
  behind it, leaving the account holding one lot of minutes and owing
  one charge. It is only past an invoice, where the withdrawal can no
  longer take the charge back, that the customer is out of pocket.
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
      account |> Prepaid.apply_standing_minutes() |> handle_result(account, period_start)
    end
  end

  defp handle_result({:ok, :no_standing_order}, _account, _period_start), do: :ok

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
