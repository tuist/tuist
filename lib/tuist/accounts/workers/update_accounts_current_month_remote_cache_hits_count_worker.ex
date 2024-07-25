defmodule Tuist.Accounts.Workers.UpdateAccountsCurrentMonthRemoteCacheHitsCountWorker do
  @moduledoc ~S"""
  This worker updates the columns current_month_remote_cache_hits_count and current_month_remote_cache_hits_count_updated_at
  which are used for billing purposes and to limit the API access and they are expensive to query.
  """
  use Oban.Worker
  import Ecto.Query
  alias Tuist.Accounts.Account
  alias Tuist.Repo
  alias Tuist.CommandEvents.Event
  alias Tuist.Projects.Project

  @impl Oban.Worker
  def perform(_job) do
    now = Tuist.Time.naive_utc_now()

    Repo.transaction(fn ->
      Repo.stream(get_accounts_with_remote_cache_hits_count_not_updated_today(now))
      |> Stream.each(&update_current_month_remote_cache_hits_count(&1, %{now: now}))
      |> Stream.run()
    end)

    :ok
  end

  def update_current_month_remote_cache_hits_count(account, %{now: now}) do
    Account.update_changeset(account, %{
      current_month_remote_cache_hits_count:
        get_current_month_remote_cache_hits_count_query(account, %{now: now}) |> Repo.one(),
      current_month_remote_cache_hits_count_updated_at: now
    })
    |> Repo.update!()
  end

  def get_accounts_with_remote_cache_hits_count_not_updated_today(now) do
    start_of_today = now |> Timex.beginning_of_day()

    from(a in Account,
      where:
        is_nil(a.current_month_remote_cache_hits_count_updated_at) or
          a.current_month_remote_cache_hits_count_updated_at < ^start_of_today
    )
  end

  def get_current_month_remote_cache_hits_count_query(%{id: account_id}, %{now: now}) do
    beginning_of_month = Timex.beginning_of_month(now)

    from c in Event,
      join: p in Project,
      on: p.id == c.project_id and p.account_id == ^account_id,
      where: c.created_at >= ^beginning_of_month,
      where: c.created_at < ^now,
      where: c.remote_cache_target_hits_count > 0 or c.remote_test_target_hits_count > 0,
      select: count(c.id)
  end
end
