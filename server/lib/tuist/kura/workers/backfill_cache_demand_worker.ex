defmodule Tuist.Kura.Workers.BackfillCacheDemandWorker do
  @moduledoc """
  Seeds `kura_account_region_lifecycles` from the cache analytics that predate
  the request-boundary demand hook.

  Enabling archival against an empty `last_cache_demand_at` would read every
  provisioned instance as inactive and archive the fleet on the first sweep.
  This worker is what stands between those two things: it is run once before
  `:kura_archival` is turned on, and the sweep additionally refuses to archive
  any account-region whose tracking is younger than its grace period, so a row
  this worker writes is inert until the live hook has had a full window to
  correct it.

  Every live account-region is seeded first, at the lookback boundary, so an
  instance whose account has been silent for longer than the window still gets
  a row. Observed demand is then overlaid on top, keeping the later timestamp.

  Four sources, unioned to the latest timestamp per account:

    * `kura_usage_events` — already account-and-region scoped, and the most
      direct evidence for accounts on Kura today.
    * `cas_events` — Xcode and Module cache traffic, project-scoped, joined to
      an account through `projects`.
    * `gradle_cache_events` — the Gradle lane, also project-scoped.
    * `command_events` with `cacheable_targets_count > 0` — CLI runs that
      touched the cache, covering accounts whose traffic predates the
      per-lane event tables.

  Seeding only. The steady-state mechanism is the request boundary
  (`Tuist.Kura.Demand`), which is why this is a manually enqueued one-off
  rather than a cron: a recurring derivation would quietly become the
  mechanism, and it cannot see a cache read that resolved an endpoint without
  producing an analytics row.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.ClickHouseRepo
  alias Tuist.Kura.AccountPolicies
  alias Tuist.Kura.Demand
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server
  alias Tuist.Projects.Project
  alias Tuist.Repo

  require Logger

  @default_lookback_days 90
  @account_batch_size 500

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    lookback_days = Map.get(args, "lookback_days", @default_lookback_days)

    since =
      DateTime.utc_now()
      |> DateTime.add(-lookback_days * 86_400, :second)
      |> DateTime.truncate(:second)

    seeded_floors = seed_live_instance_floors(since)

    demand_by_account =
      Enum.reduce(
        [kura_usage_demand(since), cas_event_demand(since), gradle_cache_demand(since), command_event_demand(since)],
        %{},
        &merge_latest/2
      )

    seeded =
      demand_by_account
      |> Map.keys()
      |> Enum.chunk_every(@account_batch_size)
      |> Enum.reduce(0, fn account_ids, seeded ->
        seeded + seed_batch(account_ids, demand_by_account)
      end)

    Logger.info(
      "[Kura.BackfillCacheDemand] seeded #{seeded_floors} live account-region floors and #{seeded} observed demand timestamps over #{lookback_days} days"
    )

    :ok
  end

  # Every live account-region gets a row first, stamped at the lookback
  # boundary, before the observed timestamps are overlaid on top of it.
  #
  # Without this the backfill covers only accounts with an analytics event
  # inside the window, so an instance whose account has been silent for longer
  # than the lookback gets no row at all. The sweep refuses to archive an
  # account-region with no row, so exactly the coldest instances — the ones the
  # whole lifecycle exists to reclaim — would be the ones it could never touch.
  #
  # The boundary is the most recent timestamp consistent with the evidence: no
  # qualifying request was observed after it. Overlaying is safe in either
  # order because the upsert keeps the later of the two, and the row still has
  # to clear the sweep's tracking grace period before it can be acted on, which
  # is the window the live request-boundary hook has to correct it.
  defp seed_live_instance_floors(since) do
    lifecycle_region_ids =
      Regions.available()
      |> Enum.reject(&Regions.private?/1)
      |> Enum.map(& &1.id)

    if lifecycle_region_ids == [] do
      0
    else
      Server
      |> where([s], s.region in ^lifecycle_region_ids)
      |> where([s], s.status not in [:destroyed, :archived])
      |> select([s], {s.account_id, s.region})
      |> Repo.all()
      |> Enum.uniq()
      |> Enum.reduce(0, fn {account_id, region}, seeded ->
        {:ok, _count} = Demand.upsert(account_id, region, since)
        seeded + 1
      end)
    end
  end

  defp merge_latest(source, acc) do
    Map.merge(acc, source, fn _account_id, left, right ->
      if DateTime.after?(left, right), do: left, else: right
    end)
  end

  defp seed_batch(account_ids, demand_by_account) do
    Account
    |> where([a], a.id in ^account_ids)
    |> preload(:subscriptions)
    |> Repo.all()
    |> Enum.reduce(0, fn account, seeded ->
      case AccountPolicies.resolve(account) do
        {:ok, %{service_region: service_region}} ->
          {:ok, _count} = Demand.upsert(account.id, service_region, Map.fetch!(demand_by_account, account.id))
          seeded + 1

        # No resolvable plan and region means no account-region instance to
        # keep warm, so there is nothing to seed.
        {:error, _reason} ->
          seeded
      end
    end)
  end

  defp kura_usage_demand(since) do
    query_demand(
      """
      SELECT account_id, max(window_start)
      FROM kura_usage_events
      WHERE window_start >= {since:DateTime} AND account_id != 0
      GROUP BY account_id
      """,
      since
    )
  end

  # `cas_events` and `gradle_cache_events` are project-scoped, so the account
  # is resolved through `projects` in Postgres rather than joined in
  # ClickHouse. The project set is bounded by the accounts that had cache
  # traffic in the window, which is the population being seeded anyway.
  defp cas_event_demand(since) do
    """
    SELECT project_id, max(inserted_at)
    FROM cas_events
    WHERE inserted_at >= {since:DateTime}
    GROUP BY project_id
    """
    |> query_demand(since)
    |> by_account()
  end

  defp gradle_cache_demand(since) do
    """
    SELECT project_id, max(inserted_at)
    FROM gradle_cache_events
    WHERE inserted_at >= {since:DateTime}
    GROUP BY project_id
    """
    |> query_demand(since)
    |> by_account()
  end

  defp command_event_demand(since) do
    """
    SELECT project_id, max(ran_at)
    FROM command_events
    WHERE ran_at >= {since:DateTime} AND cacheable_targets_count > 0
    GROUP BY project_id
    """
    |> query_demand(since)
    |> by_account()
  end

  defp query_demand(sql, since) do
    sql
    |> ClickHouseRepo.query!(%{"since" => DateTime.to_naive(since)})
    |> Map.fetch!(:rows)
    |> Map.new(fn [id, at] -> {id, to_utc(at)} end)
  end

  defp by_account(demand_by_project) when map_size(demand_by_project) == 0, do: %{}

  defp by_account(demand_by_project) do
    project_ids = Map.keys(demand_by_project)

    from(p in Project,
      where: p.id in ^project_ids,
      select: {p.id, p.account_id}
    )
    |> Repo.all()
    |> Enum.reduce(%{}, &merge_project_demand(&1, &2, demand_by_project))
  end

  defp merge_project_demand({project_id, account_id}, acc, demand_by_project) do
    candidate = Map.fetch!(demand_by_project, project_id)

    Map.update(acc, account_id, candidate, fn existing ->
      if DateTime.after?(existing, candidate), do: existing, else: candidate
    end)
  end

  defp to_utc(%DateTime{} = at), do: DateTime.truncate(at, :second)

  defp to_utc(%NaiveDateTime{} = at) do
    at |> DateTime.from_naive!("Etc/UTC") |> DateTime.truncate(:second)
  end
end
