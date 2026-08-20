defmodule Tuist.Kura.AccountPolicies do
  @moduledoc """
  Resolves an account's effective Kura plan and service region.

  `accounts.region` is the account's storage region, presented in account
  settings as where its artifacts, module cache binaries among them, are
  stored. A Kura instance holds exactly those, so an account that named a
  region is served from it and never from another, whatever the plan.

  Air runs in United States East for an account that named no region, and in
  Europe's own Air pool for an account that named Europe. Paid accounts with a
  country group resolve deterministically to that group's pool. A paid account
  that allows every region has stated no constraint, so it resolves in this
  order:

    1. its explicit versioned assignment, if an operator made one,
    2. the region its live instance is already in, so resolution never
       relocates a running account (a live one; see `live_service_regions/1`
       for why an archived instance does not hold the account to its region),
       and
    3. United States East, the deterministic default a dormant account
       receives before its next provisioning demand.

  An assignment is also the only route to a region no preference derives to.
  `accounts.region` is `all | europe | usa`, so nothing resolves to United
  States West on its own; an account is opted into it per account, for latency.

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
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server
  alias Tuist.Kura.Telemetry
  alias Tuist.Repo
  alias Tuist.Time

  @paid_service_regions %{
    europe: "eu-central",
    usa: "us-east"
  }

  # Where a paid account that has named no storage region is placed when it has
  # neither an explicit assignment nor a live instance. "All regions" in account
  # settings states no residency constraint, so a deterministic United States
  # default breaks no promise, and it is what replaces a refusal that left these
  # accounts unable to provision at all. `assign_service_region/4` remains the
  # override for one that later needs Europe.
  @default_paid_service_region "us-east"

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
      live_region: &current_live_service_region/1
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

    Map.new(accounts, fn %Account{id: id} = account ->
      {id,
       resolve(account, %{
         assignment: fn _account -> Map.get(assignments, id) end,
         live_region: fn _account -> Map.get(live_regions, id) end
       })}
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

  defp effective_service_region(%Account{region: region}, :air, _lookups) when region in [:all, :usa],
    do: {:ok, Environment.kura_air_region(region)}

  # Europe's Air pool is a separate box from the paid European one, so it
  # resolves only where the deployment serves it. Until then these accounts are
  # refused, as they are today, rather than placed in the United States: the
  # storage region they chose names the module cache binaries a Kura instance
  # holds.
  defp effective_service_region(%Account{region: :europe}, :air, _lookups) do
    region = Environment.kura_air_region(:europe)

    if Regions.available?(region) do
      {:ok, region}
    else
      {:error, :service_region_unavailable}
    end
  end

  defp effective_service_region(%Account{region: region}, plan, _lookups)
       when plan in [:pro, :enterprise] and region in [:europe, :usa],
       do: {:ok, Map.fetch!(@paid_service_regions, region)}

  defp effective_service_region(%Account{region: :all} = account, plan, lookups) when plan in [:pro, :enterprise] do
    case lookups.assignment.(account) do
      %AccountRegionPolicy{service_region: service_region} ->
        {:ok, service_region}

      nil ->
        {:ok, lookups.live_region.(account) || @default_paid_service_region}
    end
  end

  defp effective_service_region(%Account{}, :open_source, _lookups), do: {:error, :plan_not_supported}

  defp effective_service_region(%Account{}, _plan, _lookups), do: {:error, :service_region_unavailable}

  # The region an account is already being served from, or `nil` when it has no
  # live instance. Oldest first so an account holding instances in several
  # regions resolves to the one it has had longest, deterministically rather
  # than by whichever row the database returns first; an account that wants a
  # different one of them takes an explicit assignment.
  #
  # `move_phase == :none` for the same reason `Tuist.Kura` uses it: a warm
  # handoff's transient rows are internal rebalancing, not where the account
  # is served from.
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

    Server
    |> where([server], server.account_id in ^account_ids)
    |> where([server], server.status not in [:destroyed, :archived] and server.move_phase == :none)
    |> order_by([server], asc: server.inserted_at, asc: server.id)
    |> select([server], {server.account_id, server.region})
    |> Repo.all()
    |> Enum.reduce(%{}, fn {account_id, region}, regions -> Map.put_new(regions, account_id, region) end)
  end

  defp current_service_region_assignments(accounts) do
    account_ids = Enum.map(accounts, & &1.id)

    AccountRegionPolicy
    |> where([policy], policy.account_id in ^account_ids and is_nil(policy.superseded_at))
    |> Repo.all()
    |> Map.new(&{&1.account_id, &1})
  end

  defp validate_explicit_assignment(account, service_region) do
    plan = Billing.effective_plan(account)

    cond do
      plan not in [:pro, :enterprise] ->
        {:error, :plan_not_supported}

      account.region != :all ->
        {:error, :service_region_is_derived}

      service_region not in AccountRegionPolicy.service_regions() ->
        {:error, :service_region_unavailable}

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
