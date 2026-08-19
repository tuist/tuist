defmodule Tuist.Kura.Lifecycle do
  @moduledoc """
  Converges account-region Kura instances with cache demand.

  Every plan that is archived at all follows the same default 90-day lifecycle
  (`Tuist.Environment.kura_inactive_days/0`, shortened outside production so
  the archival half is exercised rather than first running for real against
  customers), and the identity rule converges in both directions:

    * an account with cache demand inside its inactivity window should have
      exactly one live instance in its service region, and
    * an account with no cache demand for a complete inactivity window should
      have none.

  Two entry points, split by cadence rather than by concern. `reconcile/0`
  runs on every reconciler tick and does everything an account can feel:
  provisioning, cancelling a drain, finishing a teardown. `sweep/0` runs daily
  and only decides that an instance has gone inactive, because that threshold
  is measured in whole days and re-deciding it every minute would change
  nothing except query volume.

  Five states, one instance:

      archived → provisioning → active → drain_pending → archived
                                  ↑            │
                                  └────────────┘

  `archived` is the resting state, not a failure, but it is not free either.
  Kura is terminal storage for what it holds: there is no object store behind
  it, and a miss is a 404 rather than an origin fetch. Archiving an
  account-region therefore *discards* that account's cache content in that
  region; the only other copy is a peer instance in another region, if the
  account has one.

  What makes that safe is not a second copy, it is that a cache miss is always
  safe. The client rebuilds what it cannot fetch and re-uploads it, so an
  account with no instance builds correctly and slowly rather than incorrectly.
  The same property covers every other gap in this loop: an instance that is
  provisioning, recovering, or refused for capacity is an account paying cold
  build times, not one that is broken.

  That cost is the whole trade. An account that has not built in a full
  inactivity window is one for which a cold rebuild on return is cheaper than
  holding its quota-enforced directory the entire time.

  The first cache demand cold-provisions. Demand while active only refreshes
  `last_cache_demand_at`. A complete inactivity window enters drain-pending,
  which unpublishes the endpoint and waits out `Kura.drain_seconds/0` before
  issuing teardown; demand arriving in that window cancels archival and the
  instance goes straight back to active. A returning account on any plan takes
  the cold-provision path, on the same row, with no expectation of prior
  content.

  ## Why archival cannot run on empty demand data

  An archival sweep against an unseeded `last_cache_demand_at` reads every
  provisioned instance as inactive and archives the fleet on its first run.
  Three things stand between this loop and that:

    * an account-region with no lifecycle row is never archived. Absence of
      demand data is not evidence of absence of demand.
    * a lifecycle row younger than the tracking grace period is never
      archived, so the backfill has a full window to land before any row it
      wrote can be acted on.
    * `keep_warm` holds a named account-region out of archival entirely, for
      the cases where a directory must survive inactivity.

  ## Plans

  Enterprise is never archived. Air and Pro follow the 90-day window, and Air
  alone can shorten to 60 under capacity pressure. Open-source accounts are
  outside the lifecycle entirely: `Tuist.Kura.AccountPolicies` resolves no
  service region for them, so they are never provisioned and never archived.

  ## Air pressure

  Air may enter drain-pending at 60 complete inactive days instead of 90, but
  only while the region's forecast enforced warm quota does not fit what is
  installed (`Tuist.Kura.Capacity`). With room, the 90-day target holds for
  every plan. Under pressure, the least-recently-demanded Air instances go
  first, and only as many as it takes to fit. No account on any plan is ever
  archived before 60 complete inactive days.
  """

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Billing
  alias Tuist.Environment
  alias Tuist.Kura
  alias Tuist.Kura.AccountPolicies
  alias Tuist.Kura.AccountRegionLifecycle
  alias Tuist.Kura.Capacity
  alias Tuist.Kura.Demand
  alias Tuist.Kura.Deployment
  alias Tuist.Kura.Provisioner
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server
  alias Tuist.Kura.Telemetry
  alias Tuist.Repo

  require Logger

  # Ceilings on how much converge work one pass does, matching the rest of the
  # reconciler. Provisioning is the tighter of the two because each one starts
  # a rollout. Anything over the ceiling is picked up by the next pass.
  @max_provisions_per_pass 20
  @max_archival_transitions_per_pass 100

  # Under capacity pressure, eligibility depends on each account's plan and so
  # is decided after the query. These bound the scan that looks past ineligible
  # rows for eligible ones: at most 1000 rows examined per region per pass.
  @provision_scan_page_size 100
  @max_provision_scan_pages 10

  @doc """
  Converges account-region instances with cache demand: provisions where
  demand has no instance, resolves drains that are due, and finishes
  teardowns. Runs on every reconciler tick, because an account waiting for its
  cache should not wait a day for it, and a drain that demand has cancelled
  should come back within a tick.

  Deciding that an instance has become inactive is not here — see `sweep/0`.
  """
  def reconcile do
    each_region(&reconcile_region/1)
  end

  @doc """
  Decides which instances have gone a complete inactive window without cache
  demand and moves them into drain-pending.

  Separate from `reconcile/0` and on a daily cadence because the thresholds
  are whole days: scanning every active instance every minute would multiply
  the query volume by three orders of magnitude and change nothing about when
  an instance is archived.
  """
  def sweep do
    each_region(&sweep_region/1)
  end

  defp each_region(fun) do
    case lifecycle_regions() do
      [] ->
        :ok

      regions ->
        # Persist buffered demand first: an account that asked for cache
        # seconds ago must not be read as inactive, and a drain must not be
        # torn down against a stale clock.
        Demand.flush()

        Enum.each(regions, fun)
    end

    :ok
  end

  # Public regions only. The private runner-cache regions are an identity rule
  # of their own (`Tuist.Kura.RunnerCache`, keyed on runner availability), and
  # archiving a node that rule wants would put the two loops in a fight.
  defp lifecycle_regions do
    Enum.reject(Regions.available(), &Regions.private?/1)
  end

  # One pressure snapshot per region per pass. Recomputing it between
  # transitions would let a single archival that relieves pressure change the
  # rule the rest of the pass runs under, which is how a loop like this
  # oscillates.
  defp reconcile_region(%Regions{id: region_id} = region) do
    pressure? = Capacity.under_pressure?(region_id)

    reconcile_drain_pending(region)
    reconcile_teardowns(region)

    case image_tag() do
      nil -> :ok
      image_tag -> reconcile_provisions(region_id, pressure?, image_tag)
    end

    :ok
  end

  defp sweep_region(%Regions{id: region_id} = region) do
    reconcile_drain_entries(region, Capacity.under_pressure?(region_id))
  end

  ## Provisioning

  # Demand inside the account's inactivity window with no live instance behind
  # it. Both shapes converge here: an account that has never had one (no
  # server row) and one returning from archive (an archived row that is reused
  # rather than replaced, because the partial uniqueness index still counts it
  # as owning the region).
  #
  # The window is the same one archival uses, which is what keeps the rule an
  # identity rather than a cycle: an instance archived for inactivity is not
  # immediately re-provisioned by the demand that failed to save it.
  defp reconcile_provisions(region_id, pressure?, image_tag) do
    region_id
    |> eligible_account_regions(pressure?)
    |> Enum.map(&provision(&1, region_id, image_tag))
    |> Enum.filter(&match?({:refused, _details}, &1))
    |> report_capacity_event(region_id)
  end

  # Without pressure the query returns only eligible rows, so one page fills
  # the pass. Under pressure the Air rows between 60 and 90 days are dropped
  # after the query, by a rule that needs each account's plan, and taking the
  # page limit before that filter would let a page of those rows consume the
  # whole pass on every tick, indefinitely hiding an older paid account that is
  # still inside its own 90-day window. So keep paging until the pass is full.
  defp eligible_account_regions(region_id, false = _pressure?) do
    account_regions_needing_instance(region_id, @max_provisions_per_pass, 0)
  end

  defp eligible_account_regions(region_id, true = _pressure?) do
    collect_eligible(region_id, 0, [])
  end

  defp collect_eligible(region_id, page, acc) when page < @max_provision_scan_pages do
    candidates = account_regions_needing_instance(region_id, @provision_scan_page_size, page * @provision_scan_page_size)
    acc = acc ++ Enum.filter(candidates, &demand_inside_window?(&1, true))

    cond do
      length(acc) >= @max_provisions_per_pass -> Enum.take(acc, @max_provisions_per_pass)
      length(candidates) < @provision_scan_page_size -> acc
      true -> collect_eligible(region_id, page + 1, acc)
    end
  end

  defp collect_eligible(region_id, _page, acc) do
    Logger.info(
      "[Kura.Lifecycle] provisioning scan for #{region_id} hit the page ceiling with #{length(acc)} eligible account-regions; the rest wait for the next pass"
    )

    Enum.take(acc, @max_provisions_per_pass)
  end

  # `id` breaks ties so paging is a total order: without it, rows sharing a
  # demand second could repeat or be skipped across pages.
  defp account_regions_needing_instance(region_id, limit, offset) do
    live_server_exists =
      from(s in Server,
        where: s.account_id == parent_as(:lifecycle).account_id,
        where: s.region == ^region_id,
        where: s.status not in [:destroyed, :archived],
        select: 1
      )

    # A destroy is an instruction, not a fault, so the demand that predates it
    # does not get to undo it. Without this the identity rule would recreate
    # the instance on the next tick and the destroy control would do nothing.
    # Demand recorded *after* the destroy is a different matter: that is a new
    # request for a cache, and it provisions like any other.
    destroyed_since_demand_exists =
      from(s in Server,
        where: s.account_id == parent_as(:lifecycle).account_id,
        where: s.region == ^region_id,
        where: s.status == :destroyed,
        where: s.updated_at >= parent_as(:lifecycle).last_cache_demand_at,
        select: 1
      )

    default_cutoff = DateTime.add(now(), -Environment.kura_inactive_days() * 86_400, :second)

    Repo.all(
      from(l in AccountRegionLifecycle,
        as: :lifecycle,
        where: l.service_region == ^region_id,
        where: l.last_cache_demand_at >= ^default_cutoff,
        where: not exists(live_server_exists),
        where: not exists(destroyed_since_demand_exists),
        order_by: [desc: l.last_cache_demand_at, asc: l.id],
        limit: ^limit,
        offset: ^offset,
        preload: [account: :subscriptions]
      )
    )
  end

  # Air's window shortens to 60 days under pressure, so its provisioning
  # window has to shorten with it. Without that, an Air instance archived
  # under pressure would be re-provisioned on the next tick by demand the
  # pressure rule had already judged too old to keep warm.
  defp demand_inside_window?(%AccountRegionLifecycle{} = lifecycle, pressure?) do
    if pressure? and Billing.effective_plan(lifecycle.account) == :air do
      cutoff = DateTime.add(now(), -Environment.kura_pressure_inactive_days() * 86_400, :second)
      DateTime.compare(lifecycle.last_cache_demand_at, cutoff) != :lt
    else
      true
    end
  end

  # Admission is re-evaluated per account rather than once for the batch: each
  # provision that succeeds consumes a slot, so a region with room for one
  # more instance must admit one account and refuse the rest.
  defp provision(%AccountRegionLifecycle{account: %Account{} = account} = lifecycle, region_id, image_tag) do
    # The lifecycle row records where demand *was* served; the policy decides
    # where it belongs *now*. They diverge when an account changes plan or
    # storage region while it has no instance — a downgrade to Open Source, or
    # a reassignment away from this region — and provisioning from the stored
    # row would resurrect the account in a region it no longer belongs to.
    case AccountPolicies.resolve(account) do
      {:ok, %{plan: plan, service_region: ^region_id}} -> admit(lifecycle, account, plan, region_id, image_tag)
      _other -> :ok
    end
  end

  defp admit(lifecycle, account, plan, region_id, image_tag) do
    case Capacity.admit(region_id, plan) do
      :ok ->
        do_provision(lifecycle, account, plan, region_id, image_tag)

      {:error, {:no_safe_slot, %{forecast_gib: forecast, installed_gib: installed}}} ->
        refuse_for_capacity(account, plan, region_id, forecast, installed)

      {:error, reason} ->
        Logger.warning(
          "[Kura.Lifecycle] could not evaluate capacity for account #{account.id} in #{region_id}: #{inspect(reason)}"
        )

        :ok
    end
  end

  defp do_provision(lifecycle, account, plan, region_id, image_tag) do
    case archived_server(account.id, region_id) do
      %Server{} = server -> return_from_archive(lifecycle, server, account, plan, image_tag)
      nil -> cold_provision(account, plan, region_id, image_tag)
    end
  end

  defp cold_provision(account, plan, region_id, image_tag) do
    case Kura.create_server(%{account_id: account.id, region: region_id, image_tag: image_tag}) do
      {:ok, _server} ->
        Telemetry.provisioned(plan, region_id, false)
        Logger.info("[Kura.Lifecycle] provisioned instance for account #{account.id} in #{region_id}")
        :ok

      {:error, reason} ->
        Logger.warning(
          "[Kura.Lifecycle] could not provision instance for account #{account.id} in #{region_id}: #{inspect(reason)}"
        )

        :ok
    end
  end

  defp return_from_archive(lifecycle, server, account, plan, image_tag) do
    case Kura.return_from_archive(server, image_tag) do
      {:ok, _server} ->
        mark_returned(lifecycle)
        Telemetry.provisioned(plan, server.region, true)
        Logger.info("[Kura.Lifecycle] returned account #{account.id} from archive in #{server.region}")
        :ok

      {:error, reason} ->
        Logger.warning(
          "[Kura.Lifecycle] could not return account #{account.id} from archive in #{server.region}: #{inspect(reason)}"
        )

        :ok
    end
  end

  # Refusing is a capacity event, not an error: the account keeps building,
  # without a cache in front of it, and the region is not overcommitted. A cold
  # build is the correct answer to "no room"; overcommitting the node is not.
  defp refuse_for_capacity(account, plan, region_id, forecast, installed) do
    Telemetry.capacity_refused(plan, region_id, forecast, installed)

    Logger.warning(
      "[Kura.Lifecycle] refused provisioning for account #{account.id} in #{region_id}: " <>
        "forecast #{forecast}GiB exceeds installed #{installed}GiB"
    )

    {:refused, %{forecast_gib: forecast, installed_gib: installed}}
  end

  # One capacity event per region per tick rather than one per refused
  # account. A full region refuses the same accounts every tick, so
  # per-account reporting would bury the signal — that the region is out of
  # room — under a repeating list of who noticed.
  defp report_capacity_event([], _region_id), do: :ok

  defp report_capacity_event([{:refused, details} | _] = refusals, region_id) do
    Sentry.capture_message("Kura region has no safe slot for new instances",
      level: :warning,
      tags: %{region: region_id},
      extra: %{
        accounts_refused: length(refusals),
        forecast_gib: details.forecast_gib,
        installed_gib: details.installed_gib,
        region: region_id
      }
    )

    :ok
  end

  defp mark_returned(%AccountRegionLifecycle{} = lifecycle) do
    lifecycle
    |> AccountRegionLifecycle.phase_changeset(%{
      drain_started_at: nil,
      teardown_started_at: nil,
      last_returned_at: now()
    })
    |> Repo.update()
  end

  defp archived_server(account_id, region_id) do
    Repo.one(
      from(s in Server,
        where: s.account_id == ^account_id and s.region == ^region_id and s.status == :archived
      )
    )
  end

  ## Entering drain-pending

  defp reconcile_drain_entries(%Regions{id: region_id}, pressure?) do
    region_id
    |> archival_candidates(pressure?)
    |> Enum.take(@max_archival_transitions_per_pass)
    |> Enum.each(fn {server, lifecycle, plan, reason} -> enter_drain(server, lifecycle, plan, reason) end)
  end

  # Ordered by least-recent demand, which is both what the pressure rule
  # requires and the right order for the default rule: the coldest instance is
  # the one whose reclamation costs least.
  defp archival_candidates(region_id, pressure?) do
    now = now()
    default_cutoff = DateTime.add(now, -Environment.kura_inactive_days() * 86_400, :second)
    pressure_cutoff = DateTime.add(now, -Environment.kura_pressure_inactive_days() * 86_400, :second)
    tracking_cutoff = DateTime.add(now, -Environment.kura_demand_tracking_grace_days() * 86_400, :second)

    region_id
    |> active_instances_with_lifecycle(pressure_cutoff, tracking_cutoff)
    |> Enum.flat_map(&classify_candidate(&1, pressure?, default_cutoff))
    |> take_pressure_candidates(region_id)
  end

  # One row per active instance whose account-region has demand tracking older
  # than the grace period and demand older than the shortest window any plan
  # can use. Keep-warm instances never appear: they hold their allocation
  # while inactive by definition.
  defp active_instances_with_lifecycle(region_id, pressure_cutoff, tracking_cutoff) do
    Repo.all(
      from(s in Server,
        join: l in AccountRegionLifecycle,
        on: l.account_id == s.account_id and l.service_region == s.region,
        where: s.region == ^region_id,
        where: s.status == :active,
        where: s.move_phase == :none,
        where: l.keep_warm == false,
        where: l.last_cache_demand_at < ^pressure_cutoff,
        where: l.inserted_at < ^tracking_cutoff,
        where: s.inserted_at < ^tracking_cutoff,
        order_by: [asc: l.last_cache_demand_at],
        preload: [account: :subscriptions],
        select: {s, l}
      )
    )
  end

  defp classify_candidate({%Server{} = server, %AccountRegionLifecycle{} = lifecycle}, pressure?, default_cutoff) do
    plan = Billing.effective_plan(server.account)

    cond do
      not archivable_plan?(plan) ->
        []

      DateTime.before?(lifecycle.last_cache_demand_at, default_cutoff) ->
        [{server, lifecycle, plan, :inactive}]

      # Between 60 and 90 complete inactive days. Only Air is eligible, and
      # only while the region is over its installed capacity.
      plan == :air and pressure? ->
        [{server, lifecycle, plan, :capacity_pressure}]

      true ->
        []
    end
  end

  # Pressure archival reclaims only as much as it takes to fit. Instances past
  # the full 90-day window are unconditional and are not counted against that
  # budget; the 60-day ones are taken in least-recent-demand order until the
  # forecast is back under the installed floor.
  defp take_pressure_candidates(candidates, region_id) do
    {pressured, unconditional} = Enum.split_with(candidates, fn {_s, _l, _p, reason} -> reason == :capacity_pressure end)

    case Capacity.installed_gib(region_id) do
      nil ->
        unconditional

      installed ->
        {:ok, region} = Regions.fetch(region_id)

        forecast =
          Enum.reduce(unconditional, Capacity.forecast_gib(region_id), fn {_s, _l, plan, _r}, gib ->
            gib - Capacity.warm_quota_gib(plan, region)
          end)

        {_final, needed} =
          Enum.reduce(pressured, {forecast, []}, fn {_s, _l, plan, _r} = candidate, {gib, taken} ->
            if gib > installed do
              {gib - Capacity.warm_quota_gib(plan, region), [candidate | taken]}
            else
              {gib, taken}
            end
          end)

        unconditional ++ Enum.reverse(needed)
    end
  end

  # The status change and the drain clock are committed together. Split across
  # two transactions, a crash between them would leave a drain-pending row with
  # no clock, and the drain window it is supposed to wait out would have no
  # start to be measured from.
  defp enter_drain(%Server{} = server, %AccountRegionLifecycle{} = lifecycle, plan, reason) do
    case Repo.transaction(fn ->
           with {:ok, drained} <- Kura.begin_drain(server),
                {:ok, _lifecycle} <-
                  lifecycle
                  |> AccountRegionLifecycle.phase_changeset(%{drain_started_at: now(), teardown_started_at: nil})
                  |> Repo.update() do
             drained
           else
             {:error, reason} -> Repo.rollback(reason)
           end
         end) do
      {:ok, _server} ->
        Telemetry.drain_pending(plan, server.region, reason)
        Logger.info("[Kura.Lifecycle] draining instance #{server.id} (#{reason})")
        :ok

      {:error, error} ->
        Logger.warning("[Kura.Lifecycle] could not drain instance #{server.id}: #{inspect(error)}")
        :ok
    end
  end

  ## Draining and archiving

  # Drain-pending instances that have not had teardown issued yet: either
  # demand came back (cancel) or the drain window elapsed (issue teardown).
  defp reconcile_drain_pending(%Regions{id: region_id}) do
    drain_cutoff = DateTime.add(now(), -Kura.drain_seconds(), :second)

    region_id
    |> draining_instances()
    |> Enum.take(@max_archival_transitions_per_pass)
    |> Enum.each(&resolve_drain(&1, drain_cutoff))
  end

  defp draining_instances(region_id) do
    Repo.all(
      from(s in Server,
        join: l in AccountRegionLifecycle,
        on: l.account_id == s.account_id and l.service_region == s.region,
        where: s.region == ^region_id,
        where: s.status == :drain_pending,
        where: is_nil(l.teardown_started_at),
        order_by: [asc: l.drain_started_at],
        preload: [account: :subscriptions],
        select: {s, l}
      )
    )
  end

  defp resolve_drain({%Server{} = server, %AccountRegionLifecycle{} = lifecycle}, drain_cutoff) do
    plan = Billing.effective_plan(server.account)

    cond do
      # Re-read at resolution, not only at selection: an account that upgrades
      # to a plan that is never archived while its instance is mid-drain gets
      # it back, rather than being reclaimed under the plan it just left.
      not archivable_plan?(plan) ->
        Logger.info("[Kura.Lifecycle] instance #{server.id} is on a plan that is never archived; returning it to service")

        cancel_drain(server, lifecycle, plan)

      lifecycle.keep_warm or demand_returned?(lifecycle) ->
        cancel_drain(server, lifecycle, plan)

      # A drain-pending row with no clock cannot have waited out its window,
      # whatever the reason the clock is missing. Start it and wait: the
      # alternative reading destroys a workload that never got its safety
      # margin.
      is_nil(lifecycle.drain_started_at) ->
        start_drain_clock(lifecycle)

      drain_window_elapsed?(lifecycle, drain_cutoff) ->
        start_teardown(server, lifecycle)

      true ->
        :ok
    end
  end

  defp start_drain_clock(%AccountRegionLifecycle{} = lifecycle) do
    {:ok, _lifecycle} =
      lifecycle
      |> AccountRegionLifecycle.phase_changeset(%{drain_started_at: now()})
      |> Repo.update()

    :ok
  end

  # Any cache demand recorded after the drain began cancels archival. Entering
  # the drain required demand older than a full inactivity window, so a
  # timestamp newer than the drain start can only be a client that came back.
  defp demand_returned?(%AccountRegionLifecycle{drain_started_at: nil}), do: false

  defp demand_returned?(%AccountRegionLifecycle{drain_started_at: started_at, last_cache_demand_at: demand_at}) do
    # At-or-after, not strictly after: both clocks are second-resolution, and
    # a request arriving in the same second the drain started is a client that
    # came back. Entering the drain required demand at least a full inactivity
    # window old, so equality can only mean new demand.
    DateTime.compare(demand_at, started_at) != :lt
  end

  # `resolve_drain/2` starts the clock before reaching here, so the drain start
  # is always set by this point.
  defp drain_window_elapsed?(%AccountRegionLifecycle{drain_started_at: started_at}, cutoff) do
    DateTime.compare(started_at, cutoff) != :gt
  end

  defp cancel_drain(%Server{} = server, %AccountRegionLifecycle{} = lifecycle, plan) do
    case Kura.cancel_drain(server) do
      {:ok, _server} ->
        {:ok, _lifecycle} =
          lifecycle
          |> AccountRegionLifecycle.phase_changeset(%{drain_started_at: nil, teardown_started_at: nil})
          |> Repo.update()

        Telemetry.archive_cancelled(plan, server.region)
        Logger.info("[Kura.Lifecycle] cancelled archival of instance #{server.id}; demand returned")
        :ok

      {:error, reason} ->
        Logger.warning("[Kura.Lifecycle] could not cancel archival of instance #{server.id}: #{inspect(reason)}")

        :ok
    end
  end

  # Past the drain window with no returning demand. Stamping
  # `teardown_started_at` before the delete is what makes this the point of no
  # return: from here new demand cold-provisions instead of cancelling, so a
  # half-deleted instance is never handed back to an account.
  defp start_teardown(%Server{} = server, %AccountRegionLifecycle{} = lifecycle) do
    {:ok, _lifecycle} =
      lifecycle
      |> AccountRegionLifecycle.phase_changeset(%{teardown_started_at: now()})
      |> Repo.update()

    destroy_backing_resource(server)
  end

  # Instances whose teardown has been issued. The delete is idempotent, so a
  # tick that finds the resource still present simply re-issues it; the row
  # only becomes archived once the resource is observably gone, which is what
  # makes "delete the pod and directory only after the drain succeeds" true
  # rather than assumed.
  #
  # The archival flag is deliberately not consulted here. Past `teardown_started_at`
  # the resource is already being deleted, and abandoning the row mid-delete
  # would strand it in drain-pending with no workload behind it. The kill
  # switch stops everything up to that point, so what it cannot stop is bounded
  # by the instances that crossed it within one tick.
  defp reconcile_teardowns(%Regions{id: region_id} = region) do
    region_id
    |> tearing_down_instances()
    |> Enum.take(@max_archival_transitions_per_pass)
    |> Enum.each(&finish_teardown(&1, region))
  end

  defp tearing_down_instances(region_id) do
    Repo.all(
      from(s in Server,
        join: l in AccountRegionLifecycle,
        on: l.account_id == s.account_id and l.service_region == s.region,
        where: s.region == ^region_id,
        where: s.status == :drain_pending,
        where: not is_nil(l.teardown_started_at),
        order_by: [asc: l.teardown_started_at],
        preload: [account: :subscriptions],
        select: {s, l}
      )
    )
  end

  defp finish_teardown({%Server{} = server, %AccountRegionLifecycle{} = lifecycle}, region) do
    case Provisioner.current_image_tag(server) do
      {:error, :not_found} ->
        complete_archival(server, lifecycle, region)

      {:ok, _image_tag} ->
        destroy_backing_resource(server)

      {:error, reason} ->
        Logger.warning("[Kura.Lifecycle] could not observe tearing-down instance #{server.id}: #{inspect(reason)}")

        :ok
    end
  end

  defp destroy_backing_resource(%Server{} = server) do
    case Provisioner.destroy(server) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("[Kura.Lifecycle] teardown failed for instance #{server.id}: #{inspect(reason)}")
        :ok
    end
  end

  # Reclaimed bytes are the enforced warm quota the instance held, which is
  # what the region gets back — not the bytes that happened to be resident,
  # which the account could refill at any time up to that quota.
  defp complete_archival(%Server{} = server, %AccountRegionLifecycle{} = lifecycle, region) do
    plan = Billing.effective_plan(server.account)
    reclaimed_bytes = Capacity.warm_quota_bytes(plan, region)
    drain_duration_ms = drain_duration_ms(lifecycle)

    case Kura.archive_server(server) do
      {:ok, _server} ->
        {:ok, _lifecycle} =
          lifecycle
          |> AccountRegionLifecycle.phase_changeset(%{
            archived_at: now(),
            last_reclaimed_bytes: reclaimed_bytes,
            last_drain_duration_ms: drain_duration_ms
          })
          |> Repo.update()

        Telemetry.archived(plan, server.region, reclaimed_bytes, drain_duration_ms)

        Logger.info(
          "[Kura.Lifecycle] archived instance #{server.id}: reclaimed #{reclaimed_bytes} bytes after #{drain_duration_ms}ms"
        )

        :ok

      {:error, reason} ->
        Logger.warning("[Kura.Lifecycle] could not archive instance #{server.id}: #{inspect(reason)}")
        :ok
    end
  end

  defp drain_duration_ms(%AccountRegionLifecycle{drain_started_at: nil}), do: 0

  defp drain_duration_ms(%AccountRegionLifecycle{drain_started_at: started_at}) do
    DateTime.diff(now(), started_at, :millisecond)
  end

  @doc """
  Records that an instance reached `:active`, with the wall-clock it took from
  the deployment that produced it.

  Called by the reconciler when activation succeeds, because that is where the
  end-to-end readiness gate lives — the endpoint answering, not the workload
  being up. A cold return is told apart from a first provision by
  `last_returned_at`, which `return_from_archive/5` stamps: on a cold return
  this is the latency an archived account pays to come back, which is exactly
  what the inactivity windows are being traded against.
  """
  def record_ready(%Server{} = server, %Deployment{inserted_at: started_at}) do
    case Repo.get_by(AccountRegionLifecycle, account_id: server.account_id, service_region: server.region) do
      nil ->
        :ok

      %AccountRegionLifecycle{} = lifecycle ->
        account = Repo.preload(server, account: :subscriptions).account

        Telemetry.ready(
          Billing.effective_plan(account),
          server.region,
          cold_return?(lifecycle, started_at),
          DateTime.diff(DateTime.utc_now(), started_at, :millisecond)
        )

        :ok
    end
  end

  defp cold_return?(%AccountRegionLifecycle{last_returned_at: nil}, _started_at), do: false

  defp cold_return?(%AccountRegionLifecycle{last_returned_at: returned_at}, started_at) do
    DateTime.compare(returned_at, started_at) != :lt
  end

  ## Gates

  # Enterprise instances are never reclaimed. The population makes the trade
  # one-sided: paid accounts are almost entirely active (58 with cache demand
  # at 90 days against 55 at 30), so archiving them frees a fraction of a
  # machine while handing the accounts with the highest support expectations
  # two cold builds on their return. A policy rather than a setting, so it does
  # not depend on anyone remembering to configure it.
  defp archivable_plan?(:enterprise), do: false
  defp archivable_plan?(_plan), do: true

  defp image_tag do
    case Environment.kura_runtime_image_tag() do
      tag when is_binary(tag) ->
        case String.trim(tag) do
          "" -> nil
          trimmed -> trimmed
        end

      _ ->
        nil
    end
  end

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)
end
