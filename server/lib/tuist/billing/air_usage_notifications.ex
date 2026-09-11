defmodule Tuist.Billing.AirUsageNotifications do
  @moduledoc """
  Queues Air usage emails once per threshold, usage period, and account admin.
  """
  import Ecto.Query

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Billing
  alias Tuist.Billing.AirUsageNotification
  alias Tuist.Billing.Workers.AirUsageNotificationWorker
  alias Tuist.CommandEvents
  alias Tuist.Repo
  alias Tuist.Runners.Allowance
  alias Tuist.Runners.Billing, as: RunnerBilling
  alias Tuist.Runners.Trials

  def enqueue(account_id, updated_at) do
    account = Repo.get!(Account, account_id)

    if current_month?(updated_at) && Billing.effective_plan(account) == :air do
      for metric <- [:remote_cache_hits, :runner_minutes], eligible?(account, metric) do
        enqueue_metric(account, updated_at, metric)
      end
    end

    {:ok, :ok}
  end

  def eligible?(account, :runner_minutes), do: not Trials.on_trial?(account)
  def eligible?(_account, :remote_cache_hits), do: true

  def usage(account, :runner_minutes) do
    now = DateTime.utc_now()
    period_start = period_start(account, now, :runner_minutes)
    minutes = account.id |> RunnerBilling.compute_milliseconds(period_start, now) |> div(60_000)
    {minutes, Allowance.free_monthly_minutes()}
  end

  def usage(account, :remote_cache_hits),
    do: {account.current_month_remote_cache_hits_count, Billing.get_payment_thresholds().remote_cache_hits}

  def period_start(account, date, metric \\ :remote_cache_hits)

  def period_start(_account, date, :runner_minutes), do: date |> Timex.beginning_of_month() |> DateTime.truncate(:second)

  def period_start(account, date, :remote_cache_hits) do
    account |> CommandEvents.usage_counted_from(date) |> DateTime.truncate(:second)
  end

  def threshold(nil, _limit), do: nil
  def threshold(usage, limit) when usage >= limit, do: 100
  def threshold(usage, limit) when usage * 100 >= limit * 80, do: 80
  def threshold(_usage, _limit), do: nil

  defp enqueue_metric(account, updated_at, metric) do
    {usage, limit} = usage(account, metric)

    if threshold = threshold(usage, limit) do
      enqueue_recipients(account, updated_at, metric, threshold, usage, limit)
    end
  end

  defp current_month?(date) do
    now = DateTime.utc_now()
    date.year == now.year and date.month == now.month
  end

  defp recipients(%Account{organization_id: nil} = account) do
    [Repo.preload(account, :user).user]
  end

  defp recipients(account) do
    account |> Repo.preload(:organization) |> Map.fetch!(:organization) |> Accounts.get_organization_members(:admin)
  end

  defp enqueue_recipients(account, updated_at, metric, threshold, usage, limit) do
    now = DateTime.truncate(DateTime.utc_now(), :second)
    period_start = period_start(account, updated_at, metric)

    notifications =
      account
      |> recipients()
      |> Enum.uniq_by(& &1.id)
      |> Enum.map(fn user ->
        %{
          account_id: account.id,
          user_id: user.id,
          metric: metric,
          period_start: period_start,
          threshold: threshold,
          usage: usage,
          limit: limit,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.transaction(fn ->
      Repo.insert_all(AirUsageNotification, notifications,
        on_conflict: :nothing,
        conflict_target: [:account_id, :user_id, :metric, :period_start, :threshold]
      )

      recipient_ids = Enum.map(notifications, & &1.user_id)

      # Lock only pending notifications, so overlapping refreshes cannot enqueue
      # duplicate jobs. Completed delivery, rather than row existence, consumes the slot.
      pending_ids =
        Repo.all(
          from(n in AirUsageNotification,
            where: n.account_id == ^account.id and n.user_id in ^recipient_ids,
            where: n.metric == ^metric and n.period_start == ^period_start and n.threshold == ^threshold,
            where: is_nil(n.delivered_at),
            order_by: n.id,
            lock: "FOR UPDATE",
            select: n.id
          )
        )

      enqueue_pending(pending_ids)
    end)
  end

  defp enqueue_pending([]), do: :ok

  defp enqueue_pending(notification_ids) do
    string_ids = Enum.map(notification_ids, &to_string/1)
    worker = Oban.Worker.to_string(AirUsageNotificationWorker)

    active_ids =
      from(j in Oban.Job,
        where: j.worker == ^worker,
        where: j.state not in ["completed", "cancelled", "discarded"],
        where: fragment("?->>'notification_id'", j.args) in ^string_ids,
        select: j.args
      )
      |> Repo.all()
      |> MapSet.new(& &1["notification_id"])

    notification_ids
    |> Enum.reject(&MapSet.member?(active_ids, &1))
    |> Enum.map(&AirUsageNotificationWorker.new(%{notification_id: &1}))
    |> Oban.insert_all()
  end
end
