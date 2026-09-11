defmodule Tuist.Kura.Workers.SeedProjectCacheDemandWorker do
  @moduledoc """
  Gives an account with no Kura instance one when it creates a project, so an
  instance exists by the time anything asks the cache for an endpoint.

  Provisioning is otherwise triggered by the first cache-endpoint resolution,
  and the account has no instance until that completes. Creating a project is
  an earlier signal that builds are coming, so the wait is spent before anyone
  is waiting on it. This removes the provisioning wait, not the cold cache: a
  new instance starts empty either way, because Kura is terminal storage with
  no object store behind it.

  Seeding a lifecycle row is the whole mechanism, the same one
  `Tuist.Kura.Workers.BackfillCacheDemandWorker` uses; the reconciler
  provisions from it. Creating the instance here would be a second path into
  provisioning that re-derives the plan, claim size, image tag and region.

  The condition is the account having no live instance rather than a project
  count, so it also covers an account that predates Kura. A private
  runner-cache instance does not count, for the same reason
  `Tuist.Kura.AccountPolicies` never resolves into one.

  ## What this must not disturb

  **Archival.** A row written here is an ordinary `last_cache_demand_at`
  timestamp, so an account that never builds is archived after a full
  inactivity window like any other. A probation rule keyed on bytes moved
  since an instance entered service would instead archive a seeded instance in
  a fortnight and hold the account-region out of provisioning. None is in the
  tree (#12609, which proposed one, was closed unmerged); if one lands it has
  to start its clock at the account's first endpoint resolution, because an
  instance seeded here has moved no bytes by construction.

  **Placement.** No placer decision is recorded. A seed is a guess — the
  origin of a project-creation request is where somebody clicked in a
  dashboard, not where CI will run — and `Tuist.Kura.Placement`'s
  `correct_initial` rung only fires while the primary was never decided.

  **Capacity.** A seed is speculative, so a region over its pressure line
  declines and the refusal is counted rather than retried. The account is
  still provisioned the ordinary way once it asks for the cache, where the
  scheduler decides admission from each pod's ephemeral-storage request.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [keys: [:account_id], period: 300, states: :incomplete]

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Kura.AccountPolicies
  alias Tuist.Kura.Capacity
  alias Tuist.Kura.Demand
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server
  alias Tuist.Kura.Telemetry
  alias Tuist.Repo

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_id" => account_id}}) do
    case Repo.one(from(a in Account, where: a.id == ^account_id, preload: :subscriptions)) do
      nil -> :ok
      account -> seed(account)
    end
  end

  defp seed(%Account{} = account) do
    if serving_instance?(account) do
      :ok
    else
      case AccountPolicies.resolve(account) do
        # A plan or storage region with no pool behind it has nowhere to be
        # seeded. `AccountPolicies.resolve/1` counts the refusal itself.
        {:error, _reason} -> :ok
        {:ok, resolution} -> seed_region(account, resolution)
      end
    end
  end

  defp seed_region(%Account{} = account, %{plan: plan, service_region: service_region}) do
    if Capacity.under_pressure?(service_region) do
      Telemetry.seed_declined(plan, service_region, :capacity_pressure)

      Logger.info(
        "[Kura.SeedProjectCacheDemand] did not seed account #{account.id} into #{service_region}: the region is over its pressure line"
      )

      :ok
    else
      {:ok, _count} = Demand.upsert(account.id, service_region, DateTime.utc_now())
      :ok
    end
  end

  defp serving_instance?(%Account{id: account_id}) do
    Repo.exists?(
      from(s in Server,
        where: s.account_id == ^account_id,
        where: s.status not in [:destroyed, :archived],
        where: s.region not in ^private_region_ids()
      )
    )
  end

  defp private_region_ids do
    Regions.all()
    |> Enum.filter(&Regions.private?/1)
    |> Enum.map(& &1.id)
  end
end
