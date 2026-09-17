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

  **Archival.** A seeded instance that stores nothing is reclaimed once it has
  been in service for `Tuist.Environment.kura_unused_days/0`
  (`Tuist.Kura.Lifecycle`). The account's first cache request returns it, so
  reclaiming it early costs one provision. The seed declines while that hold is
  in place (`Tuist.Kura.Demand.archived_hold/1`); otherwise every new project
  would provision the reclaimed instance again. The same holds for an instance
  that was brought up ahead of its account's demand and archived before
  anything used it: waking it here would spend the capacity archiving it
  released, with no request through Kura to show it is wanted.

  **Placement.** The job carries `origin`, the coarse location label of the
  request that created the project (never an address). The seed is placed
  nearest it rather than in the default region
  (`AccountPolicies.resolve_with_origin_hint/2`), and that region is recorded
  as the account's primary, because provisioning resolves again without the
  hint and would otherwise skip it. Where somebody created a project is not
  necessarily where CI will run, so the record is a guess rather than a
  decision (`PlacerRegion.guess?/1`): `Tuist.Kura.Placement`'s
  `correct_initial` rung only fires while the primary was never decided, and
  it moves the account once its own runs say otherwise. A seed without an
  origin, or one declined for capacity, records nothing.

  **Capacity.** A seed is speculative, so a region under capacity pressure
  (`Tuist.Kura.Capacity.under_pressure?/1`) declines and the refusal is counted
  rather than retried. The account is still provisioned the ordinary way once
  it asks for the cache, where the scheduler decides admission from each pod's
  ephemeral-storage request.
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
  alias Tuist.Kura.PlacerRegion
  alias Tuist.Kura.PlacerRegions
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server
  alias Tuist.Kura.Telemetry
  alias Tuist.Repo

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_id" => account_id} = args}) do
    case Repo.one(from(a in Account, where: a.id == ^account_id, preload: :subscriptions)) do
      nil -> :ok
      account -> seed(account, Map.get(args, "origin"))
    end
  end

  defp seed(%Account{} = account, origin) do
    if serving_instance?(account) do
      :ok
    else
      case AccountPolicies.resolve_with_origin_hint(account, origin) do
        # A plan or storage region with no pool behind it has nowhere to be
        # seeded. `AccountPolicies.resolve_with_origin_hint/2` counts the
        # refusal itself.
        {:error, _reason} -> :ok
        {:ok, resolution} -> seed_region(account, resolution, origin)
      end
    end
  end

  defp seed_region(%Account{} = account, %{plan: plan, service_region: service_region}, origin) do
    cond do
      reason = Demand.archived_hold(account) ->
        Telemetry.seed_declined(plan, service_region, reason)

        Logger.info(
          "[Kura.SeedProjectCacheDemand] did not seed account #{account.id}: its instance is archived (#{reason}) until the account asks for it"
        )

        :ok

      Capacity.under_pressure?(service_region) ->
        Telemetry.seed_declined(plan, service_region, :capacity_pressure)

        Logger.info(
          "[Kura.SeedProjectCacheDemand] did not seed account #{account.id} into #{service_region}: the region is under capacity pressure"
        )

        :ok

      true ->
        record_guess(account, service_region, origin)
        {:ok, _count} = Demand.upsert(account.id, service_region, DateTime.utc_now())
        :ok
    end
  end

  # Insert-only: a primary the account already holds is the region resolution
  # chose here anyway, so it is left as it is.
  defp record_guess(%Account{} = account, service_region, origin) when is_binary(origin) do
    PlacerRegions.record_first_primary(account, service_region, %{
      "signal" => PlacerRegion.creation_origin_signal()
    })

    :ok
  end

  defp record_guess(_account, _service_region, _origin), do: :ok

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
