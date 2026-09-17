defmodule Tuist.Kura.Workers.SeedLegacyCacheDemandWorker do
  @moduledoc """
  Seeds Kura cache demand for accounts whose clients still use the legacy
  Tuist-hosted cache nodes (`cache-*.tuist.dev`), so each has an instance
  serving before those clients are routed to Kura.

  A client that does not send the `kura` feature flag is handed the legacy
  nodes and never records demand (`Tuist.Kura.Demand`), so nothing provisions
  an instance for its account. Once every client resolves through Kura, such
  an account gets no endpoint until its first request has provisioned one, and
  released CLIs fail on an empty endpoint list.

  Legacy traffic is read from `command_events` (module cache runs),
  `cas_events` (Xcode) and `gradle_cache_events`, by the endpoint each request
  went to. Demand is stamped at the account's latest legacy request, never
  later than now, and resolved to regions the way the demand flush resolves
  it. Seeding a lifecycle row is the whole mechanism, as in
  `Tuist.Kura.Workers.BackfillCacheDemandWorker`: the reconciler provisions
  from it, and its gates read the stamp as they read any demand. An operator
  destroy newer than the account's last legacy request still holds, and an
  instance archived for storing nothing returns only if the account used the
  legacy nodes after the archival. Both are reported rather than seeded.

  Accounts already served are seeded too, which keeps their inactivity clock
  on the traffic their clients actually send.

  ## Capacity

  Accounts are admitted per region against the headroom
  `Tuist.Kura.Admission` enforces, paid plans first and then by legacy
  traffic. An account with no instance, no assignment and no placement
  decision that does not fit is spilled to the nearest permitted region that
  has room, recorded as first placement records a capacity spill, so
  `Tuist.Kura.Placement` can correct it later. An account that fits nowhere is
  reported and not seeded: the reconciler would retry its refused provision on
  every tick.

  ## Preparing

  With `prepare`, an instance is brought up and then archived as soon as it is
  active (`Tuist.Kura.Lifecycle.archive_prepared/2`), so the slow part of a
  first provision is done ahead of time and the instance holds no capacity
  until its account asks for it through Kura. The job runs in passes a minute
  apart: each pass archives what the previous ones brought up and seeds the
  next accounts into the room that frees, until nothing is on its way.

  Only instances the backfill brought up are archived, at most once each. The
  job records the demand it seeded each account-region with, and an instance
  whose account has recorded demand after that, through Kura, is left in
  service, however recent the account's legacy traffic is. Legacy traffic
  never returns a prepared instance; only a request through Kura does.

  ## Running it

  `dry_run` defaults to true: the plan is taken in a transaction that is rolled
  back, because resolution can record a placement. `run/1` returns the report
  and the job logs it. `lookback_days` defaults to 7.

  An instance that stores nothing for `Tuist.Environment.kura_unused_days/0` is
  archived, and these instances store nothing until their clients are routed
  to Kura. Seed shortly before that routing change deploys. Running it again is
  safe and returns anything archived in between.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Billing
  alias Tuist.ClickHouseRepo
  alias Tuist.Environment
  alias Tuist.Kura.AccountPolicies
  alias Tuist.Kura.AccountRegionLifecycle
  alias Tuist.Kura.AccountRegionPolicy
  alias Tuist.Kura.Admission
  alias Tuist.Kura.Capacity
  alias Tuist.Kura.Demand
  alias Tuist.Kura.Lifecycle
  alias Tuist.Kura.OriginMap
  alias Tuist.Kura.PlacerClaims
  alias Tuist.Kura.PlacerRegion
  alias Tuist.Kura.PlacerRegions
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server
  alias Tuist.Kura.Telemetry
  alias Tuist.Projects.Project
  alias Tuist.Repo

  require Logger

  @default_lookback_days 7
  # Module cache runs record the URL the CLI used; Xcode and Gradle events record
  # the host the node reported, with no scheme.
  @legacy_endpoint_pattern "^(https://)?cache-[a-z0-9-]+[.]tuist[.]dev(:[0-9]+)?/?$"
  @plan_order %{enterprise: 0, pro: 1, air: 2}
  @not_live [:destroyed, :archived]
  # Whole-window scans of the cache event tables, far past the repo's per-request budget.
  @scan_seconds 300
  @pass_seconds 60
  @max_prepare_seconds 24 * 3600
  @transitional_statuses [:provisioning, :replicating, :drain_pending]

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    args =
      if Map.get(args, "prepare", false),
        do: Map.put_new(args, "started_at", DateTime.to_iso8601(now())),
        else: args

    report = run(args)
    log_report(report)

    if next_pass?(report) do
      args = Map.merge(args, %{"prepared" => report.prepared, "seeded" => report.seeded})
      {:ok, _job} = Oban.update_job(job, %{args: args})
      {:snooze, @pass_seconds}
    else
      :ok
    end
  end

  defp next_pass?(%{prepare: true, dry_run: false, in_flight: true, started_at: started_at}),
    do: DateTime.diff(now(), started_at) < @max_prepare_seconds

  defp next_pass?(_report), do: false

  @doc """
  Plans the seed and, unless `"dry_run"` is `true` (the default), applies it.
  Returns the report.
  """
  def run(args \\ %{}) do
    dry_run? = Map.get(args, "dry_run", true)
    now = now()
    since = DateTime.add(now, -Map.get(args, "lookback_days", @default_lookback_days) * 86_400, :second)

    options = %{
      prepare?: Map.get(args, "prepare", false),
      started_at: started_at(args, now),
      prepared: MapSet.new(Map.get(args, "prepared", [])),
      seeded: Map.get(args, "seeded", %{})
    }

    traffic = legacy_traffic(since, now)
    accounts = accounts_by_priority(traffic)

    plan =
      case Repo.transaction(fn -> plan_and_apply(accounts, traffic, options, dry_run?) end) do
        {:ok, plan} -> plan
        {:error, {:dry_run, plan}} -> plan
      end

    Map.merge(plan, %{
      dry_run: dry_run?,
      since: since,
      prepare: options.prepare?,
      started_at: options.started_at,
      in_flight: Enum.any?(plan.entries, & &1.in_flight)
    })
  end

  defp started_at(%{"started_at" => started_at}, _now) do
    {:ok, started_at, _offset} = DateTime.from_iso8601(started_at)
    started_at
  end

  defp started_at(_args, now), do: now

  defp plan_and_apply(accounts, traffic, options, dry_run?) do
    plan = plan(accounts, traffic, options)

    if dry_run? do
      Repo.rollback({:dry_run, plan})
    else
      apply_plan(plan, options)
    end
  end

  ## Legacy traffic

  defp legacy_traffic(since, now) do
    [
      lane_traffic(:module, "command_events", "ran_at", since),
      lane_traffic(:xcode, "cas_events", "inserted_at", since),
      lane_traffic(:gradle, "gradle_cache_events", "inserted_at", since)
    ]
    |> Enum.concat()
    |> by_account(now)
  end

  defp lane_traffic(lane, table, timestamp, since) do
    """
    SELECT project_id, count(), max(#{timestamp})
    FROM #{table}
    WHERE #{timestamp} >= {since:DateTime} AND match(cache_endpoint, {pattern:String})
    GROUP BY project_id
    """
    |> ClickHouseRepo.query!(%{"since" => DateTime.to_naive(since), "pattern" => @legacy_endpoint_pattern},
      settings: [max_execution_time: @scan_seconds],
      timeout: to_timeout(second: @scan_seconds + 30)
    )
    |> Map.fetch!(:rows)
    |> Enum.map(fn [project_id, events, last_at] -> {project_id, lane, events, to_utc(last_at)} end)
  end

  defp by_account([], _now), do: %{}

  defp by_account(rows, now) do
    project_ids = rows |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

    account_by_project =
      from(p in Project, where: p.id in ^project_ids, select: {p.id, p.account_id})
      |> Repo.all()
      |> Map.new()

    Enum.reduce(rows, %{}, fn {project_id, lane, events, last_at}, acc ->
      case Map.fetch(account_by_project, project_id) do
        {:ok, account_id} ->
          observed = %{events: events, last_at: Enum.min([last_at, now], DateTime), lanes: [lane]}
          Map.update(acc, account_id, observed, &merge_traffic(&1, observed))

        :error ->
          acc
      end
    end)
  end

  defp merge_traffic(left, right) do
    %{
      events: left.events + right.events,
      last_at: Enum.max([left.last_at, right.last_at], DateTime),
      lanes: Enum.sort(Enum.uniq(left.lanes ++ right.lanes))
    }
  end

  defp accounts_by_priority(traffic) when map_size(traffic) == 0, do: []

  defp accounts_by_priority(traffic) do
    account_ids = Map.keys(traffic)

    from(a in Account, where: a.id in ^account_ids, preload: :subscriptions)
    |> Repo.all()
    |> Enum.sort_by(fn account ->
      {Map.get(@plan_order, Billing.effective_plan(account), map_size(@plan_order)), -traffic[account.id].events,
       account.id}
    end)
  end

  ## Planning

  defp plan([], _traffic, options),
    do: %{entries: [], regions: %{}, prepared: MapSet.to_list(options.prepared), seeded: options.seeded}

  defp plan(accounts, traffic, options) do
    context = %{
      prepare?: options.prepare?,
      started_at: options.started_at,
      prepared: options.prepared,
      seeded: options.seeded,
      traffic: traffic,
      inactive_cutoff: DateTime.add(DateTime.utc_now(), -Environment.kura_inactive_days() * 86_400, :second),
      resolutions: AccountPolicies.serving_regions_all(accounts),
      origins: AccountPolicies.majority_origins(accounts),
      servers: servers_by_account(accounts),
      lifecycles: lifecycles_by_account(accounts),
      decided: decided_account_ids(accounts)
    }

    {entries, regions} = Enum.flat_map_reduce(accounts, %{}, &plan_account(&1, context, &2))

    %{entries: entries, regions: regions, prepared: MapSet.to_list(options.prepared), seeded: options.seeded}
  end

  defp plan_account(account, context, ledger) do
    base = %{
      account_id: account.id,
      handle: account.name,
      plan: Billing.effective_plan(account),
      origin: Map.get(context.origins, account.id),
      legacy: Map.fetch!(context.traffic, account.id),
      kura: context.servers |> Map.get(account.id, []) |> Enum.map(&%{region: &1.region, status: &1.status}),
      region: nil,
      preferred_region: nil,
      outcome: nil,
      reason: nil,
      kura_status: nil,
      reservation_gib: nil,
      server_id: nil,
      in_flight: false
    }

    case Map.fetch!(context.resolutions, account.id) do
      {:ok, [primary | _] = regions} ->
        Enum.flat_map_reduce(regions, ledger, fn region, ledger ->
          plan_region(%{base | region: region}, account, region == primary, context, ledger)
        end)

      {:error, reason} ->
        {[%{base | outcome: :skipped, reason: reason}], ledger}
    end
  end

  defp plan_region(entry, account, primary?, context, ledger) do
    servers = Map.get(context.servers, account.id, [])
    lifecycle = lifecycle(context, account, entry.region)

    case Enum.find(servers, &(&1.region == entry.region and &1.status not in @not_live)) do
      nil -> plan_absent(entry, account, lifecycle, primary? and spillable?(account, servers, context), context, ledger)
      live -> {[plan_live(entry, live, lifecycle, context)], ledger}
    end
  end

  defp plan_live(entry, %Server{status: :active} = live, lifecycle, context) do
    if prepare?(entry, live, lifecycle, context),
      do: %{entry | outcome: :prepare, kura_status: :active, server_id: live.id, in_flight: true},
      else: %{entry | outcome: :serving, kura_status: :active}
  end

  defp plan_live(entry, live, lifecycle, context) do
    in_flight =
      context.prepare? and live.status in @transitional_statuses and Map.has_key?(context.seeded, prepared_key(entry)) and
        brought_up?(live, lifecycle, context)

    %{entry | outcome: :waiting, kura_status: live.status, in_flight: in_flight}
  end

  defp plan_absent(entry, account, lifecycle, spillable?, context, ledger) do
    cond do
      context.prepare? and prepared_archive?(lifecycle) ->
        {[%{entry | outcome: :prepared}], ledger}

      reason = blocked(entry, account, entry.region, context) ->
        {[%{entry | outcome: :skipped, reason: reason}], ledger}

      true ->
        admit(entry, account, spillable?, context, ledger)
    end
  end

  defp lifecycle(context, account, region_id) do
    context.lifecycles |> Map.get(account.id, []) |> Enum.find(&(&1.service_region == region_id))
  end

  # An instance the backfill seeded and brought up, whose account has recorded
  # no demand since the seed, and that the backfill has not archived before.
  # Compared with the seed rather than the latest legacy request: legacy
  # traffic keeps arriving, and a Kura request older than the last legacy one
  # still means the account uses the instance.
  defp prepare?(entry, server, lifecycle, %{prepare?: true} = context) do
    case seeded_at(context.seeded, entry) do
      %DateTime{} = seeded_at ->
        not MapSet.member?(context.prepared, prepared_key(entry)) and brought_up?(server, lifecycle, context) and
          not is_nil(lifecycle) and not DateTime.after?(lifecycle.last_cache_demand_at, seeded_at)

      nil ->
        false
    end
  end

  defp prepare?(_entry, _server, _lifecycle, _context), do: false

  defp brought_up?(server, lifecycle, context) do
    DateTime.compare(service_started_at(server, lifecycle), context.started_at) != :lt
  end

  defp service_started_at(%Server{inserted_at: inserted_at}, %AccountRegionLifecycle{
         last_returned_at: %DateTime{} = returned_at
       }), do: Enum.max([inserted_at, returned_at], DateTime)

  defp service_started_at(%Server{inserted_at: inserted_at}, _lifecycle), do: inserted_at

  defp prepared_archive?(%AccountRegionLifecycle{drain_reason: :prepared, archived_at: %DateTime{}}), do: true
  defp prepared_archive?(_lifecycle), do: false

  defp prepared_key(entry), do: "#{entry.account_id}:#{entry.region}"

  defp seeded_at(seeded, entry) do
    case Map.fetch(seeded, prepared_key(entry)) do
      {:ok, at} ->
        {:ok, seeded_at, _offset} = DateTime.from_iso8601(at)
        seeded_at

      :error ->
        nil
    end
  end

  # The reasons `Tuist.Kura.Lifecycle` would not provision the account-region
  # from demand stamped at the account's last legacy request.
  defp blocked(entry, account, region_id, context) do
    lifecycle = lifecycle(context, account, region_id)
    demand_at = demand_at(entry.legacy.last_at, lifecycle)

    cond do
      DateTime.before?(demand_at, context.inactive_cutoff) ->
        :inactive

      destroyed_after?(Map.get(context.servers, account.id, []), region_id, demand_at) ->
        :destroyed_after_demand

      reason = archived_after(lifecycle, demand_at) ->
        reason

      true ->
        nil
    end
  end

  defp admit(entry, account, spillable?, context, ledger) do
    {fits?, gib, ledger} = reserve(ledger, account, entry.region)

    cond do
      fits? ->
        {[%{entry | outcome: :provision, reservation_gib: gib, in_flight: true}],
         count(ledger, entry.region, :provisions)}

      spillable? ->
        spill(entry, account, context, ledger)

      true ->
        {[%{entry | outcome: :skipped, reason: :capacity_exhausted}], count(ledger, entry.region, :refused)}
    end
  end

  defp spill(entry, account, context, ledger) do
    placeable = AccountPolicies.placeable_regions(account)

    siblings =
      entry.origin
      |> OriginMap.candidates()
      |> Enum.filter(&(&1 in placeable and &1 != entry.region))
      |> Enum.reject(&blocked(entry, account, &1, context))

    case reserve_first(siblings, account, ledger) do
      {{sibling, gib}, ledger} ->
        spilled = %{
          entry
          | outcome: :provision,
            region: sibling,
            preferred_region: entry.region,
            reservation_gib: gib,
            in_flight: true
        }

        ledger =
          ledger
          |> count(entry.region, :spilled_out)
          |> count(sibling, :spilled_in)
          |> count(sibling, :provisions)

        {[spilled], ledger}

      {nil, ledger} ->
        {[%{entry | outcome: :skipped, reason: :capacity_exhausted}], count(ledger, entry.region, :refused)}
    end
  end

  defp reserve_first(region_ids, account, ledger) do
    Enum.reduce_while(region_ids, {nil, ledger}, fn region_id, {nil, ledger} ->
      case reserve(ledger, account, region_id) do
        {true, gib, ledger} -> {:halt, {{region_id, gib}, ledger}}
        {false, _gib, ledger} -> {:cont, {nil, ledger}}
      end
    end)
  end

  # Reserves the account's instance in the region's ledger when it fits, the
  # way `Tuist.Kura.Admission.admit?/2` would admit it after everything already
  # planned for the region.
  defp reserve(ledger, account, region_id) do
    ledger = open(ledger, region_id)
    {:ok, region} = Regions.fetch(region_id)
    gib = Capacity.resident_gib(region, candidate(account, region))
    %{headroom_gib: headroom, admitted_gib: admitted} = Map.fetch!(ledger, region_id)

    if fits?(headroom, admitted + gib) do
      {true, gib, put_in(ledger, [region_id, :admitted_gib], admitted + gib)}
    else
      {false, gib, ledger}
    end
  end

  defp fits?(:unbounded, _gib), do: true
  defp fits?(headroom, gib) when is_integer(headroom), do: gib <= headroom
  defp fits?(nil, _gib), do: false

  defp open(ledger, region_id) do
    Map.put_new_lazy(ledger, region_id, fn ->
      {:ok, region} = Regions.fetch(region_id)

      %{
        headroom_gib: Admission.headroom_gib(region),
        admitted_gib: 0,
        provisions: 0,
        refused: 0,
        spilled_in: 0,
        spilled_out: 0
      }
    end)
  end

  defp count(ledger, region_id, key) do
    ledger
    |> open(region_id)
    |> update_in([region_id, key], &(&1 + 1))
  end

  defp candidate(account, region) do
    %Server{
      account: account,
      account_id: account.id,
      region: region.id,
      status: :provisioning,
      storage_claim_size: if(Regions.storage_governed?(region), do: PlacerClaims.effective_claim_size(account))
    }
  end

  defp demand_at(legacy_at, %AccountRegionLifecycle{last_cache_demand_at: %DateTime{} = recorded}),
    do: Enum.max([legacy_at, recorded], DateTime)

  defp demand_at(legacy_at, _lifecycle), do: legacy_at

  defp destroyed_after?(servers, region_id, demand_at) do
    Enum.any?(servers, fn server ->
      server.region == region_id and server.status == :destroyed and
        DateTime.compare(server.updated_at, demand_at) != :lt
    end)
  end

  # Archived for never storing anything, or before anything used it, after the
  # account's last demand: only demand recorded after the archival returns it.
  defp archived_after(%AccountRegionLifecycle{drain_reason: reason, archived_at: %DateTime{} = archived_at}, demand_at)
       when reason in [:unused, :prepared] do
    if DateTime.compare(demand_at, archived_at) != :gt, do: :"archived_#{reason}_after_demand"
  end

  defp archived_after(_lifecycle, _demand_at), do: nil

  defp spillable?(%Account{id: account_id}, servers, context) do
    not MapSet.member?(context.decided, account_id) and not Enum.any?(servers, &(&1.status not in @not_live))
  end

  defp servers_by_account(accounts) do
    account_ids = Enum.map(accounts, & &1.id)
    private_region_ids = Regions.all() |> Enum.filter(&Regions.private?/1) |> Enum.map(& &1.id)

    from(s in Server,
      where: s.account_id in ^account_ids and s.region not in ^private_region_ids and s.move_phase == :none,
      order_by: [asc: s.inserted_at, asc: s.id]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.account_id)
  end

  defp lifecycles_by_account(accounts) do
    account_ids = Enum.map(accounts, & &1.id)

    from(l in AccountRegionLifecycle, where: l.account_id in ^account_ids)
    |> Repo.all()
    |> Enum.group_by(& &1.account_id)
  end

  defp decided_account_ids(accounts) do
    account_ids = Enum.map(accounts, & &1.id)
    placed = accounts |> PlacerRegions.primary_regions() |> Map.keys()

    assigned =
      Repo.all(
        from(policy in AccountRegionPolicy,
          where: policy.account_id in ^account_ids and is_nil(policy.superseded_at),
          select: policy.account_id
        )
      )

    MapSet.new(placed ++ assigned)
  end

  ## Applying

  defp apply_plan(%{entries: entries} = plan, options) do
    Enum.each(entries, &record_spill/1)

    # Preparing seeds each account-region once and refreshes nothing: a clock
    # moved by legacy traffic would read as the account asking for an instance
    # it never used.
    seeding = Enum.filter(entries, &seed?(&1, plan.seeded, options))

    rows =
      Enum.map(seeding, fn entry ->
        %{account_id: entry.account_id, service_region: entry.region, last_cache_demand_at: entry.legacy.last_at}
      end)

    {:ok, _count} = Demand.upsert_many(rows)

    seeded =
      if options.prepare?,
        do: Map.merge(plan.seeded, Map.new(seeding, &{prepared_key(&1), DateTime.to_iso8601(&1.legacy.last_at)})),
        else: plan.seeded

    archived =
      for %{outcome: :prepare} = entry <- entries,
          :ok == Lifecycle.archive_prepared(Repo.get!(Server, entry.server_id), seeded_at(seeded, entry)),
          do: prepared_key(entry)

    %{plan | prepared: Enum.uniq(plan.prepared ++ archived), seeded: seeded}
  end

  defp seed?(%{outcome: :provision} = entry, seeded, %{prepare?: true}), do: not Map.has_key?(seeded, prepared_key(entry))
  defp seed?(_entry, _seeded, %{prepare?: true}), do: false
  defp seed?(%{outcome: outcome}, _seeded, _options), do: outcome in [:provision, :serving, :waiting]

  defp record_spill(%{outcome: :provision, preferred_region: preferred} = entry) when is_binary(preferred) do
    evidence = %{
      "signal" => PlacerRegion.capacity_spill_signal(),
      "preferred_region" => preferred,
      "plan" => to_string(entry.plan)
    }

    case PlacerRegions.record_first_primary(%Account{id: entry.account_id}, entry.region, evidence) do
      {:recorded, _row} -> Telemetry.placement_capacity_spill(entry.plan, preferred, entry.region)
      {:existing, _row} -> :ok
    end
  end

  defp record_spill(_entry), do: :ok

  ## Report

  defp log_report(report) do
    mode =
      cond do
        report.dry_run -> "dry run"
        report.prepare -> "prepare pass (in flight: #{report.in_flight}, prepared so far: #{length(report.prepared)})"
        true -> "seeded"
      end

    accounts = report.entries |> Enum.map(& &1.account_id) |> Enum.uniq() |> length()

    Logger.info(
      "[Kura.SeedLegacyCacheDemand] #{mode}: #{accounts} accounts with legacy cache traffic since #{DateTime.to_iso8601(report.since)}, #{length(report.entries)} account-regions"
    )

    Enum.each(report.entries, &Logger.info("[Kura.SeedLegacyCacheDemand] #{format_entry(&1)}"))

    report.entries
    |> Enum.frequencies_by(&{&1.outcome, &1.reason})
    |> Enum.each(fn {{outcome, reason}, count} ->
      Logger.info("[Kura.SeedLegacyCacheDemand] outcome=#{outcome} reason=#{reason} count=#{count}")
    end)

    Enum.each(report.regions, fn {region_id, region} ->
      Logger.info(
        "[Kura.SeedLegacyCacheDemand] region=#{region_id} headroom_gib=#{region.headroom_gib} admitted_gib=#{region.admitted_gib} provisions=#{region.provisions} spilled_in=#{region.spilled_in} spilled_out=#{region.spilled_out} refused=#{region.refused}"
      )
    end)
  end

  defp format_entry(entry) do
    kura = Enum.map_join(entry.kura, ",", &"#{&1.region}:#{&1.status}")

    "account=#{entry.account_id} handle=#{entry.handle} plan=#{entry.plan} outcome=#{entry.outcome} reason=#{entry.reason} " <>
      "region=#{entry.region} preferred_region=#{entry.preferred_region} origin=#{entry.origin} " <>
      "reservation_gib=#{entry.reservation_gib} kura_status=#{entry.kura_status} kura=#{kura} " <>
      "lanes=#{Enum.join(entry.legacy.lanes, ",")} events=#{entry.legacy.events} last_legacy_at=#{DateTime.to_iso8601(entry.legacy.last_at)}"
  end

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)

  defp to_utc(%DateTime{} = at), do: DateTime.truncate(at, :second)
  defp to_utc(%NaiveDateTime{} = at), do: at |> DateTime.from_naive!("Etc/UTC") |> DateTime.truncate(:second)
end
