defmodule Tuist.Kura.RunnerCache do
  @moduledoc """
  Keeps a private runner-cache Kura node provisioned for exactly the
  accounts that have runners-as-a-service turned on.

  The identity rule converges both directions every tick, per private
  region:

    * an account with at least one Runner Profile whose platform the
      region serves (`Regions.runner_platforms`) AND an explicit
      `:runners` FunWithFlags toggle should have exactly one
      non-destroyed Kura server in that region, and
    * an account with no such profiles — or without the flag — should
      have none there.

  Profiles are the durable "this account uses runners" marker: dispatch
  resolves every `runs-on` through them, so an account without profiles
  cannot receive jobs and a cache node would idle. The platform match
  keeps the node next to the fleet it serves: a region pinned beside
  the Scaleway Mac mini fleet provisions only for accounts with macOS
  profiles, and an account that drops its last macOS profile frees that
  node even while its Linux profiles keep a node in a Linux-serving
  region.

  The flag check is the explicit `FunWithFlags.enabled?(:runners, for:
  account)` gate, deliberately NOT `FeatureFlags.runners_enabled?/1` —
  that helper short-circuits to `true` outside production, which here
  would provision a cache node for every dev account with auto-created
  profiles and exhaust the kura node pool. A dedicated infra node is an
  explicit opt-in in every environment.

  This runs inside `Tuist.Kura.Reconciler`'s tick rather than on its own
  cron, so it shares the same cadence and self-heals after a BEAM
  restart: enabling runners provisions the node on the next tick;
  disabling them tears it down. It is a no-op unless a private region is
  available in this runtime (via `TUIST_KURA_AVAILABLE_REGIONS`) and a
  Kura runtime image tag is configured, so non-managed and not-yet-wired
  environments stay inert.

  Provisioning the node does not, by itself, route any traffic to it —
  `Tuist.Kura.runner_cache_endpoint_url/2` only returns a URL once the
  node is `:active`, and runner dispatch resolves that lazily.
  """

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Kura
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server
  alias Tuist.Repo
  alias Tuist.Runners.Profile

  require Logger

  @max_provision_candidates_per_tick 100

  @doc """
  Converges runner-cache nodes with runner enablement. Safe to call on
  every reconciler tick; returns `:ok`.
  """
  def reconcile do
    Enum.each(runner_cache_regions(), &reconcile_region/1)
  end

  defp reconcile_region(%Regions{id: region_id} = region) do
    # Tear down first so an account that flips runners off frees its node
    # even when no image tag is configured to provision new ones.
    Enum.each(nodes_to_tear_down(region), &tear_down/1)

    case image_tag() do
      nil ->
        :ok

      image_tag ->
        Enum.each(accounts_needing_node(region), &provision(&1, region_id, image_tag))
        # A node that failed before its first successful deployment
        # (transient apiserver error, missing CRD field, ...) would
        # otherwise strand its account forever: the server row exists,
        # so provisioning never re-runs, and nothing else retries
        # failed servers. Self-heal them on the same cadence.
        Enum.each(nodes_to_retry(region_id), &retry(&1, image_tag))
    end

    :ok
  end

  # The private (runner-cache) regions available in this runtime —
  # usually zero or one per environment, but an environment may run one
  # region per fleet locality (e.g. a Linux-serving node pool in the
  # umbrella cluster plus a macOS-serving pool in Scaleway fr-par).
  # Multi-region went from unsupported-and-logged to a first-class
  # shape when regions gained `runner_platforms`: each region now
  # reconciles independently against the accounts whose profiles it
  # serves, so none is ever silently un-reconciled. `available/0` is
  # env-gated, so this stays empty until a private region is wired
  # into `TUIST_KURA_AVAILABLE_REGIONS`.
  defp runner_cache_regions do
    Enum.filter(Regions.available(), &Regions.private?/1)
  end

  # Platforms a region's nodes serve. Private regions always declare
  # `runner_platforms`; the fallback keeps a malformed region from
  # matching every profile.
  defp region_platforms(%Regions{runner_platforms: platforms}) when is_list(platforms), do: platforms
  defp region_platforms(_), do: []

  defp image_tag do
    case Tuist.Environment.kura_runtime_image_tag() do
      tag when is_binary(tag) ->
        case String.trim(tag) do
          "" -> nil
          trimmed -> trimmed
        end

      _ ->
        nil
    end
  end

  defp accounts_needing_node(%Regions{id: region_id} = region) do
    platforms = region_platforms(region)

    server_exists =
      from(s in Server,
        where:
          s.account_id == parent_as(:account).id and s.region == ^region_id and
            s.status != :destroyed,
        select: 1
      )

    profile_exists =
      from(p in Profile,
        where: p.account_id == parent_as(:account).id,
        where: p.platform in ^platforms,
        select: 1
      )

    # The SQL narrows to "has profiles, lacks a node"; the flag check
    # runs per account in Elixir because FunWithFlags gates are
    # actor-scoped (and can be set via a global boolean gate, so they
    # can't be pre-joined as a column). In prod the candidate set is
    # tiny (runner customers), but in an env with the flag globally on
    # and many auto-profile accounts it isn't — cap the SQL load so a
    # tick reads a bounded number of rows into BEAM. Provisioning is
    # convergent, so any overflow is picked up on the next tick; a
    # capped tick is logged so a growing backlog is visible.
    candidates =
      Repo.all(
        from(a in Account,
          as: :account,
          where: exists(profile_exists),
          where: not exists(server_exists),
          limit: @max_provision_candidates_per_tick
        )
      )

    if length(candidates) == @max_provision_candidates_per_tick do
      Logger.warning("kura.runner_cache: provision candidate query hit the per-tick cap",
        cap: @max_provision_candidates_per_tick,
        region: region_id
      )
    end

    candidates
    |> Enum.filter(&runner_cache_enabled?/1)
    |> Enum.map(& &1.id)
  end

  defp nodes_to_tear_down(%Regions{id: region_id} = region) do
    platforms = region_platforms(region)

    profile_exists =
      from(p in Profile,
        where: p.account_id == parent_as(:server).account_id,
        where: p.platform in ^platforms,
        select: 1
      )

    no_profiles =
      Repo.all(
        from(s in Server,
          as: :server,
          where: s.region == ^region_id,
          where: s.status not in [:destroying, :destroyed],
          where: not exists(profile_exists),
          select: s
        )
      )

    flag_off =
      from(s in Server,
        as: :server,
        join: a in assoc(s, :account),
        where: s.region == ^region_id,
        where: s.status not in [:destroying, :destroyed],
        where: exists(profile_exists),
        preload: [account: a]
      )
      |> Repo.all()
      |> Enum.reject(&runner_cache_enabled?(&1.account))

    no_profiles ++ flag_off
  end

  defp runner_cache_enabled?(account), do: FunWithFlags.enabled?(:runners, for: account)

  defp provision(account_id, region_id, image_tag) do
    case Kura.create_server(%{account_id: account_id, region: region_id, image_tag: image_tag}) do
      {:ok, _server} ->
        Logger.info("[Kura.RunnerCache] provisioned runner-cache node for account #{account_id} in #{region_id}")
        :ok

      {:error, reason} ->
        Logger.warning(
          "[Kura.RunnerCache] could not provision runner-cache node for account #{account_id} in #{region_id}: #{inspect(reason)}"
        )

        :ok
    end
  end

  # Failed servers that never had a successful deployment
  # (`current_image_tag` nil) — the only state `Kura.retry_server/2`
  # accepts. Failures after a successful deploy keep their node and are
  # an operator concern, not ours.
  defp nodes_to_retry(region_id) do
    Repo.all(
      from(s in Server,
        where: s.region == ^region_id,
        where: s.status == :failed,
        where: is_nil(s.current_image_tag),
        select: s
      )
    )
  end

  defp retry(%Server{} = server, image_tag) do
    case Kura.retry_server(server, image_tag) do
      {:ok, _server} ->
        Logger.info("[Kura.RunnerCache] retrying failed runner-cache node #{server.id}")
        :ok

      {:error, reason} ->
        Logger.warning("[Kura.RunnerCache] could not retry runner-cache node #{server.id}: #{inspect(reason)}")

        :ok
    end
  end

  defp tear_down(%Server{} = server) do
    case Kura.destroy_server(server) do
      {:ok, _server} ->
        Logger.info("[Kura.RunnerCache] tearing down runner-cache node #{server.id} (runners disabled)")
        :ok

      {:error, reason} ->
        Logger.warning("[Kura.RunnerCache] could not tear down runner-cache node #{server.id}: #{inspect(reason)}")

        :ok
    end
  end
end
