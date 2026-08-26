defmodule Tuist.Kura.AccountPolicies do
  @moduledoc """
  Resolves an account's effective Kura plan and service region.

  `accounts.region` is the account's storage region, presented in account
  settings as where its artifacts, module cache binaries among them, are
  stored. A Kura instance holds exactly those, so an account that named a
  region is served from it and never from another, whatever the plan.

  Air runs in United States East for an account that named no region, and in
  whichever region the deployment serves Air from in Europe for an account that
  named Europe. Paid accounts with a country group resolve deterministically to
  that group's pool. A paid account
  that allows every region has stated no constraint, so it resolves in this
  order:

    1. its explicit versioned assignment, if an operator made one,
    2. the region its live public instance is already in, so resolution never
       relocates a running account, and
    3. United States East, the deterministic default a dormant account
       receives before its next provisioning demand.

  An assignment is the only route *here* to a region no preference derives to.
  `accounts.region` is `all | europe | usa`, so nothing resolves to United
  States West or Asia Pacific Southeast on its own; an account is opted into
  either per account, for latency. Asia Pacific has no derivation rule for the
  same reason United States West has none: there is no `accounts.region` value
  that names it. So an APAC account is pinned there by an operator, or resolves
  to United States East like any other account that stated no constraint.

  Resolution is not the only way an account gets a server in a region, and this
  module is not a gate on that. A customer can also add one directly from
  account settings in any region `Regions.selectable/0` offers, which never
  consults this module. What resolution decides is where the control plane
  *places* an account — demand, lifecycle, provisioning — not what the customer
  is permitted to pick.

  Step 2 counts only live instances in public regions, and picks one when there
  are several; `live_service_regions/1` carries the reasoning for both, and for
  why an archive does not hold an account to its region.

  Step 2 is what keeps the default from being a migration. Without it an
  account already serving from elsewhere would start recording demand against
  the default region, cold-provision a second instance there, and leave the
  original holding its allocation with no reclamation path on the plans that
  are never archived.
  """

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.User
  alias Tuist.Billing
  alias Tuist.Environment
  alias Tuist.Kura.AccountRegionPolicy
  alias Tuist.Kura.OriginMap
  alias Tuist.Kura.Origins
  alias Tuist.Kura.PlacerRegions
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server
  alias Tuist.Kura.Telemetry
  alias Tuist.Repo
  alias Tuist.Time

  # Where an account is placed when nothing else decides: no assignment, no
  # placement decision, nothing already running, and no origin to read. A
  # deterministic default breaks no residency promise, and it is what these
  # accounts resolve to today.
  @residency_defaults %{
    europe: "eu-central",
    usa: "us-east",
    all: "us-east"
  }

  @doc """
  Returns the effective plan and service region for an account.

  An account whose plan or storage region has no Kura pool behind it receives
  an error rather than a region it cannot be served from. Every refusal is
  counted (`Tuist.Kura.Telemetry.resolution_refused/2`): a refused account is
  simply left on whatever lane it is already on and raises nothing, so without
  the counter a whole class of accounts can sit unprovisioned indefinitely with
  no signal that they are.
  """
  def resolve(%Account{} = account) do
    resolve(account, %{
      assignment: &current_service_region_assignment/1,
      live_region: &current_live_service_region/1,
      placer_region: &PlacerRegions.primary_region/1,
      origin: &majority_origin/1
    })
  end

  @doc """
  Resolves many accounts at once, loading every explicit service-region
  assignment and every live instance region in one query each.

  `resolve/1` costs two queries per account that allows every storage region,
  which is fine for a handful of accounts and not fine on the demand-flush
  hot path, where the batch is every account that used the cache in the last
  minute.
  """
  def resolve_all(accounts) when is_list(accounts) do
    assignments = current_service_region_assignments(accounts)
    live_regions = live_service_regions(accounts)
    placer_regions = PlacerRegions.primary_regions(accounts)
    origins = majority_origins(accounts)

    Map.new(accounts, fn %Account{id: id} = account ->
      {id,
       resolve(account, %{
         assignment: fn _account -> Map.get(assignments, id) end,
         live_region: fn _account -> Map.get(live_regions, id) end,
         placer_region: fn _account -> Map.get(placer_regions, id) end,
         origin: fn _account -> Map.get(origins, id) end
       })}
    end)
  end

  @doc """
  `serving_regions/1` for many accounts at once, for the demand-flush hot
  path. Returns `{:ok, [region | secondaries]}` or the resolution's error, per
  account id.
  """
  def serving_regions_all(accounts) when is_list(accounts) do
    resolutions = resolve_all(accounts)
    secondaries = PlacerRegions.serving_regions_all(accounts)

    Map.new(accounts, fn %Account{id: id} = account ->
      case Map.fetch!(resolutions, id) do
        {:ok, %{service_region: primary}} ->
          permitted = permitted_regions(account)

          extra =
            secondaries
            |> Map.get(id, [])
            |> Enum.reject(&(&1 == primary))
            |> Enum.filter(&(&1 in permitted))

          {id, {:ok, [primary | extra]}}

        {:error, reason} ->
          {id, {:error, reason}}
      end
    end)
  end

  defp resolve(%Account{} = account, lookups) do
    plan = Billing.effective_plan(account)

    case effective_service_region(account, plan, lookups) do
      {:ok, service_region} ->
        {:ok, %{plan: plan, service_region: service_region}}

      {:error, reason} ->
        Telemetry.resolution_refused(plan, reason)
        {:error, reason}
    end
  end

  @doc """
  The plan an account's Kura instance is sized from — its memory profile and
  the claim its data volume is built at.

  A self-hosted deployment has no subscriptions, so `Billing.effective_plan/1`
  would resolve every account there to `:air`. Its Enterprise license is the
  entitlement, matching how `Tuist.Billing.Entitlements.allowed_features/2`
  grants everything off the hosted server.
  """
  def sizing_plan(%Account{} = account) do
    if Environment.tuist_hosted?(), do: Billing.effective_plan(account), else: :enterprise
  end

  @doc """
  Assigns one service region to a paid account that currently allows every
  storage region.

  Each assignment appends a version and supersedes the previous current row in
  the same transaction.
  """
  def assign_service_region(%Account{id: account_id}, service_region, %User{id: assigned_by_user_id}, reason)
      when is_binary(service_region) and is_binary(reason) do
    Repo.transaction(fn ->
      account =
        Account
        |> where([account], account.id == ^account_id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      with %Account{} <- account,
           :ok <- validate_explicit_assignment(account, service_region),
           version = next_version(account.id),
           now = DateTime.truncate(Time.utc_now(), :second),
           :ok <- supersede_current(account.id, now),
           {:ok, assignment} <-
             insert_assignment(
               account.id,
               service_region,
               version,
               assigned_by_user_id,
               reason
             ) do
        assignment
      else
        nil -> Repo.rollback(:account_not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def assign_service_region(%Account{}, _service_region, %User{}, _reason), do: {:error, :invalid_assignment}

  @doc """
  Restores a historical assignment by appending its service region as a new
  current version.
  """
  def restore_service_region(%Account{id: account_id} = account, version, %User{} = assigned_by_user, reason)
      when is_integer(version) and version > 0 and is_binary(reason) do
    case Repo.get_by(AccountRegionPolicy, account_id: account_id, version: version) do
      %AccountRegionPolicy{service_region: service_region} ->
        assign_service_region(account, service_region, assigned_by_user, reason)

      nil ->
        {:error, :assignment_not_found}
    end
  end

  def restore_service_region(%Account{}, _version, %User{}, _reason), do: {:error, :assignment_not_found}

  @doc "Returns the current explicit service-region assignment for an account."
  def current_service_region_assignment(%Account{id: account_id}) do
    Repo.one(
      from(policy in AccountRegionPolicy,
        where: policy.account_id == ^account_id and is_nil(policy.superseded_at)
      )
    )
  end

  @doc "Returns every explicit service-region assignment, newest version first."
  def list_service_region_history(%Account{id: account_id}) do
    Repo.all(
      from(policy in AccountRegionPolicy,
        where: policy.account_id == ^account_id,
        order_by: [desc: policy.version]
      )
    )
  end

  # Air is funded per region rather than served everywhere, so its candidates
  # are the funded ones its residency admits. An Air account whose residency
  # admits no funded region is refused, exactly as an account restricted to
  # Europe is today, and the refusal is counted: sustained refused demand is
  # what an Air budget in a new region gets decided from.
  defp effective_service_region(%Account{} = account, :air, lookups) do
    case account |> permitted_regions() |> restrict_to_plan(:air) do
      [] ->
        {:error, :service_region_unavailable}

      placeable ->
        {:ok, place(account, placeable, placeable, lookups)}
    end
  end

  defp effective_service_region(%Account{} = account, plan, lookups) when plan in [:pro, :enterprise] do
    permitted = permitted_regions(account)

    case lookups.assignment.(account) do
      %AccountRegionPolicy{service_region: service_region} ->
        assigned_service_region(service_region)

      nil ->
        # Only a served region can be chosen fresh. Resolving into one the
        # catalog lists but the deployment does not serve would record demand
        # in a region `Lifecycle.lifecycle_regions/0` never iterates, which is
        # the same trap `assigned_service_region/1` guards against.
        placeable = Enum.filter(permitted, &Regions.available?/1)

        {:ok, place(account, permitted, placeable, lookups)}
    end
  end

  defp effective_service_region(%Account{}, :open_source, _lookups), do: {:error, :plan_not_supported}

  defp effective_service_region(%Account{}, _plan, _lookups), do: {:error, :service_region_unavailable}

  # In order: what placement decided, then where the account is already served
  # from, then where its traffic comes from, then the residency default.
  #
  # Placement outranks stickiness because an applied relocation is exactly a
  # decision to stop being sticky; stickiness outranks origin because moving a
  # running account is a relocation, which is a decision taken on a window of
  # evidence rather than on the request in hand. So origin decides for accounts
  # with nothing running, which is what first placement is.
  defp place(account, permitted, placeable, lookups) do
    from_placement = Enum.find([lookups.placer_region.(account), lookups.live_region.(account)], &(&1 in permitted))

    from_placement || from_origin(account, placeable, lookups) || residency_default(account)
  end

  # An unattributed account still comes through here, because the mapping
  # table's default order is also the order to choose in when there is nothing
  # to go on. What an origin adds is a different order, not the only one.
  defp from_origin(account, placeable, lookups) do
    origin = lookups.origin.(account)
    preferred = OriginMap.preferred(origin, placeable)

    # Only an account we can locate can be served further away than it should
    # be. An unattributed one expresses no preference, so there is nothing here
    # to leave unmet and nothing to procure against.
    if not is_nil(origin) do
      wanted = origin |> OriginMap.candidates() |> hd()

      if preferred != wanted, do: Telemetry.placement_preference_unmet(origin, wanted, preferred)
    end

    preferred
  end

  # Where an account lands when nothing else decides. Unchanged from what these
  # accounts resolve to today, so an origin nobody could attribute and a region
  # nobody has funded both leave the answer exactly as it was.
  defp residency_default(%Account{region: region}), do: Map.fetch!(@residency_defaults, region)

  # Which regions the account's residency admits. The promise is about where
  # data may live, and more than one region can keep it: an account that
  # answered "United States" is admitted to both American regions, and never to
  # either European one.
  @doc """
  Every region the account should be running an instance in: its service
  region, plus the secondaries placement added alongside it.

  `resolve/1` still answers with one region, because one region is what a
  demand row, a provisioning decision and an endpoint answer are each about.
  This is the set that has more than one member, and the lifecycle iterates it.
  """
  def serving_regions(%Account{} = account) do
    case resolve(account) do
      {:ok, %{service_region: primary}} ->
        secondaries =
          account
          |> PlacerRegions.serving_regions()
          |> Enum.reject(&(&1 == primary))
          |> Enum.filter(&(&1 in permitted_regions(account)))

        [primary | secondaries]

      {:error, _reason} ->
        []
    end
  end

  @doc """
  The regions an account may actually be placed in: the ones its residency
  admits, that this deployment serves, and that carry a budget for its plan.

  The constraint resolver the placer consumes. `resolve/1` decides where an
  account goes; this says where it is allowed to go, and the difference
  between the two is what a placement decision is.
  """
  def placeable_regions(%Account{} = account, plan) do
    account
    |> permitted_regions()
    |> Enum.filter(&Regions.available?/1)
    |> restrict_to_plan(plan)
  end

  # Air is funded per region; the paid plans are served wherever the
  # deployment serves.
  defp restrict_to_plan(regions, :air), do: Enum.filter(regions, &(&1 in Environment.kura_air_region_ids()))
  defp restrict_to_plan(regions, _plan), do: regions

  defp permitted_regions(%Account{region: residency}) do
    Regions.admitted_by_residency(residency)
  end

  # How far back first placement reads. Long enough that a weekend does not
  # erase where an account works, short enough to still be "where its traffic
  # comes from" rather than where it once came from. Relocating an account
  # already running is a decision the placer takes on much longer windows;
  # this only answers for an account with nothing to relocate.
  @origin_window_days 7

  defp majority_origin(%Account{id: account_id} = account) do
    account
    |> List.wrap()
    |> majority_origins()
    |> Map.get(account_id)
  end

  defp majority_origins(accounts) do
    since = Date.add(Date.utc_today(), -@origin_window_days)

    accounts
    |> Enum.map(& &1.id)
    |> Origins.rollups_since(since)
    |> Map.new(fn {account_id, rollups} -> {account_id, majority_origin_of(rollups)} end)
  end

  # Runs decide. Resolutions decide only when there are no runs at all, which
  # is the account whose very first request this is: biased evidence about
  # where it is beats no evidence and the default region.
  defp majority_origin_of(rollups) do
    by_origin = Enum.group_by(rollups, & &1.origin)

    leader(by_origin, & &1.run_count) || leader(by_origin, & &1.demand_count)
  end

  defp leader(by_origin, count) do
    by_origin
    |> Enum.map(fn {origin, rollups} -> {origin, rollups |> Enum.map(count) |> Enum.sum()} end)
    |> Enum.reject(fn {_origin, total} -> total == 0 end)
    |> case do
      [] -> nil
      totals -> totals |> Enum.max_by(fn {origin, total} -> {total, origin} end) |> elem(0)
    end
  end

  # An assignment names a region; `Regions.available?/1` decides whether it is
  # served. Both gates are needed: an assignment to an unserved region would
  # otherwise resolve cleanly, record demand under a region
  # `Lifecycle.lifecycle_regions/0` never iterates, and report `provisioning:
  # true` from `Demand.instance_expected?/1` indefinitely.
  #
  # Refused rather than fallen back to the default region, because silently
  # relocating an explicitly assigned account is what an assignment exists to
  # prevent. The row is untouched and resolves once the region is served.
  defp assigned_service_region(service_region) do
    if Regions.available?(service_region) do
      {:ok, service_region}
    else
      {:error, :service_region_unavailable}
    end
  end

  # The region an account is already being served from, or `nil` when it has no
  # live instance.
  #
  # Private runner-cache regions do not count. They are provisioned by a
  # separate identity rule (`Tuist.Kura.RunnerCache`, keyed on runner
  # availability), they are never CLI-facing, and `Lifecycle.lifecycle_regions/0`
  # rejects them, so resolving an account into one would record demand in a
  # region nothing provisions against and leave it with no developer-facing
  # cache at all. An account whose only live instance is a runner cache is, for
  # this purpose, an account with none.
  #
  # `move_phase == :none` for the same reason `Tuist.Kura` uses it: a warm
  # handoff's transient rows are internal rebalancing, not where the account
  # is served from.
  #
  # Among what is left, oldest wins, ordered by `(inserted_at, id)`. That is a
  # total order, so the answer is reproducible rather than dependent on which
  # row the database happens to return first. It is deliberately not an attempt
  # to solve multi-region: an account holding public instances in several
  # regions keeps exactly one under this rule, and the choice between
  # same-day instances comes down to sub-second ordering. Such an account wants
  # an explicit assignment naming the region it should be resolved to, which is
  # a decision rather than something to infer from timestamps.
  #
  # Archived rows are excluded, which is a decision rather than a detail: an
  # account's region is deliberately not sticky across an archive. Archival
  # discards that account's cache content in the region, so there is nothing
  # left there to return to and a cold return is a cold return wherever it
  # lands. Honouring an archived row instead would hold a claim on a region the
  # account no longer occupies and send the return into it even when it is the
  # region under pressure. The consequence is that accounts allowing every
  # region drift toward the default across archive cycles, which is a sizing
  # input for the other regions rather than a correctness problem.
  defp current_live_service_region(%Account{id: account_id} = account) do
    account
    |> List.wrap()
    |> live_service_regions()
    |> Map.get(account_id)
  end

  defp live_service_regions(accounts) do
    account_ids = Enum.map(accounts, & &1.id)
    private_region_ids = private_region_ids()

    Server
    |> where([server], server.account_id in ^account_ids)
    |> where([server], server.status not in [:destroyed, :archived] and server.move_phase == :none)
    |> where([server], server.region not in ^private_region_ids)
    |> order_by([server], asc: server.inserted_at, asc: server.id)
    |> select([server], {server.account_id, server.region})
    |> Repo.all()
    |> Enum.reduce(%{}, fn {account_id, region}, regions -> Map.put_new(regions, account_id, region) end)
  end

  # Read from the catalog rather than listed, so a region added as private is
  # excluded here without anyone remembering to update this.
  defp private_region_ids do
    Regions.all()
    |> Enum.filter(&Regions.private?/1)
    |> Enum.map(& &1.id)
  end

  defp current_service_region_assignments(accounts) do
    account_ids = Enum.map(accounts, & &1.id)

    AccountRegionPolicy
    |> where([policy], policy.account_id in ^account_ids and is_nil(policy.superseded_at))
    |> Repo.all()
    |> Map.new(&{&1.account_id, &1})
  end

  # An assignment may name any region the account's residency admits, not only
  # the ones an unconstrained account can reach. A customer restricted to the
  # United States has two regions to be served from, and pinning it to the
  # nearer one breaks no promise it made.
  defp validate_explicit_assignment(account, service_region) do
    plan = Billing.effective_plan(account)

    cond do
      plan not in [:pro, :enterprise] ->
        {:error, :plan_not_supported}

      service_region not in AccountRegionPolicy.service_regions() ->
        {:error, :service_region_unavailable}

      service_region not in permitted_regions(account) ->
        {:error, :service_region_outside_residency}

      true ->
        :ok
    end
  end

  defp next_version(account_id) do
    AccountRegionPolicy
    |> where([policy], policy.account_id == ^account_id)
    |> Repo.aggregate(:max, :version)
    |> case do
      nil -> 1
      version -> version + 1
    end
  end

  defp supersede_current(account_id, now) do
    AccountRegionPolicy
    |> where([policy], policy.account_id == ^account_id and is_nil(policy.superseded_at))
    |> Repo.update_all(set: [superseded_at: now, updated_at: now])

    :ok
  end

  defp insert_assignment(account_id, service_region, version, assigned_by_user_id, reason) do
    %{
      account_id: account_id,
      service_region: service_region,
      version: version,
      assigned_by_user_id: assigned_by_user_id,
      reason: reason
    }
    |> AccountRegionPolicy.create_changeset()
    |> Repo.insert()
  end
end
