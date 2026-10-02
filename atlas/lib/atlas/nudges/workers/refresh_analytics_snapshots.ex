defmodule Atlas.Nudges.Workers.RefreshAnalyticsSnapshots do
  @moduledoc """
  Cron fan-out for the nudge analytics pipeline. Once a day, enqueues:

    * `RefreshMetricBucketForAccount` for yesterday's UTC-day bucket, for
      every candidate account.
    * `RefreshAirStatusForAccount` for the current billing period, for
      every candidate account.

  Both per-account workers are Oban-deduped hourly, so a manual re-run
  the same day is a soft no-op.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  import Ecto.Query

  alias Atlas.Accounts.Account
  alias Atlas.Nudges.Workers.RefreshAirStatusForAccount
  alias Atlas.Nudges.Workers.RefreshMetricBucketForAccount
  alias Atlas.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    yesterday = Date.utc_today() |> Date.add(-1) |> Date.to_iso8601()

    for account_id <- candidate_account_ids() do
      %{"account_id" => account_id, "bucket_date" => yesterday}
      |> RefreshMetricBucketForAccount.new()
      |> Oban.insert()

      %{"account_id" => account_id}
      |> RefreshAirStatusForAccount.new()
      |> Oban.insert()
    end

    :ok
  end

  # Same shape as the v1 candidate query on `Atlas.Nudges.Signals.InvitedTeammatesSso`:
  # paying customers whose account has not been marked "not an account."
  def candidate_account_ids do
    Account
    |> where([a], not is_nil(a.plan_tier) and a.plan_tier != "free")
    |> where([a], is_nil(a.not_an_account_at))
    |> select([a], a.id)
    |> Repo.all()
  end
end
