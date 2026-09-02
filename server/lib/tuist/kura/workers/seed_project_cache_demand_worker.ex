defmodule Tuist.Kura.Workers.SeedProjectCacheDemandWorker do
  @moduledoc """
  Gives an account with no Kura instance one when it creates a project, so an
  instance exists by the time anything asks the cache for an endpoint.

  Provisioning is otherwise triggered by the first cache-endpoint resolution:
  `Tuist.Kura.Demand.record/2` buffers the account, the flush writes a
  lifecycle row, and the next `Tuist.Kura.Lifecycle.reconcile/0` tick
  provisions from it. Until that completes the account has no instance, so the
  answer carries `provisioning: true` with a short cache and the client is
  served from whatever lane is still up. Creating a project is a strong, early
  signal that builds are coming, and it happens well before the first cache
  request, so the wait can be spent before anyone is waiting on it.

  What this removes is the *provisioning wait*, not the cold cache. A new
  instance starts empty either way: Kura is terminal storage with no object
  store behind it, and a first instance has no peer to sync from. The first
  build still misses everything and uploads what it builds. What it no longer
  does is miss because there was nowhere to look.

  ## Seeding demand rather than provisioning directly

  Writing a lifecycle row with recent demand is the whole mechanism; the
  reconciler does the rest, exactly as it does for a cache request.
  `Tuist.Kura.Workers.BackfillCacheDemandWorker` seeds the same way. Creating
  the instance here instead would mean a second path into provisioning that
  has to re-derive the plan, the claim size, the image tag and the region, and
  would diverge from the demand path the first time any of them changed.

  ## Triggered by the account having no instance, not by a project count

  An account creating its second project while its first instance is live
  needs nothing. An account that predates Kura and still has none has exactly
  the problem this exists to fix, whether the project is its first or its
  twentieth, so the condition is the instance rather than the project.

  A live instance in a private runner-cache region does not count, for the
  same reason `Tuist.Kura.AccountPolicies` does not resolve into one: it is
  never CLI-facing and the lifecycle never iterates its region, so an account
  holding only that one has no developer-facing cache at all.

  An account whose instance was archived is seeded like any other, and returns
  from archive on the next tick. Somebody creating a project is at least as
  strong a request for a cache as the login-time endpoint resolution that
  un-archives accounts today.

  ## What this must not disturb

  **Archival.** The only archival clock is `last_cache_demand_at`, and a row
  written here is an ordinary demand timestamp on it: an account that never
  builds is archived after a full inactivity window
  (`Tuist.Environment.kura_inactive_days/0`), like any other account that
  stopped. The version of this that would bite is a probation rule keyed on
  bytes moved since an instance entered service, which would archive a seeded
  instance in a fortnight and then hold the account-region out of provisioning
  for an inactivity window — locking out exactly the account this is trying to
  help. No such rule is in the tree (#12609, which proposed one, was closed
  unmerged). If one lands, it needs to start its clock at the account's first
  endpoint resolution rather than at the instance entering service, because an
  instance seeded here has by construction moved no bytes yet.

  **Placement.** No placer decision is recorded. A seed is a guess by
  construction — the origin of a project-creation request is where somebody
  clicked in a dashboard, not where CI will run — and `Tuist.Kura.Placement`'s
  `correct_initial` rung only fires while the primary region was never
  decided. Writing a decision here would spend the one correction the account
  gets on the weakest evidence it will ever produce.

  **Capacity.** A seed is speculative: nobody has built yet. Spending a
  region's last room on one while the lifecycle is shortening Air's window to
  claw space back is the wrong trade, so a region over its pressure line
  declines and the refusal is counted. Nothing retries; the account is
  provisioned the ordinary way the moment it actually asks for the cache,
  which is where admission belongs — every cache pod requests its claim's
  worth of ephemeral storage, so the scheduler is what decides whether a real
  instance fits.
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
