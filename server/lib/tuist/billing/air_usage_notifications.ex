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
  alias Tuist.Repo
  alias Tuist.Runners.Allowance
  alias Tuist.Runners.Billing, as: RunnerBilling
  alias Tuist.Runners.Trials

  def enqueue(account_id, updated_at) do
    Repo.transaction(fn ->
      account = Repo.one!(from(a in Account, where: a.id == ^account_id, lock: "FOR UPDATE"))

      if current_month?(updated_at) && Billing.effective_plan(account) == :air do
        # Two independent allowances, each with its own threshold and counting window.
        for metric <- [:remote_cache_hits, :runner_minutes], eligible?(account, metric) do
          enqueue_metric(account, updated_at, metric)
        end
      end
    end)
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
    month_start = date |> Timex.beginning_of_month() |> DateTime.truncate(:second)

    case account.free_tier_reset_at do
      %DateTime{} = reset_at -> Enum.max_by([month_start, reset_at], &DateTime.to_unix/1)
      nil -> month_start
    end
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

    # The durable unique key survives Oban job pruning and overlapping refreshes.
    {_count, inserted} =
      Repo.insert_all(AirUsageNotification, notifications,
        on_conflict: :nothing,
        conflict_target: [:account_id, :user_id, :metric, :period_start, :threshold],
        returning: [:id]
      )

    inserted
    |> Enum.map(&AirUsageNotificationWorker.new(%{notification_id: &1.id}))
    |> Oban.insert_all()
  end
end
