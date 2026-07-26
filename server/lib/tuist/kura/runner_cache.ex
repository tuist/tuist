defmodule Tuist.Kura.RunnerCache do
  @moduledoc """
  Keeps a private runner-cache Kura node provisioned for exactly the
  accounts that can use hosted runners.

  The identity rule converges both directions every tick, per private
  region:

    * an account with at least one Runner Profile whose platform the
      region serves (`Regions.runner_platforms`) AND
      `Tuist.FeatureFlags.runners_enabled?/1` returning true should have exactly one
      non-destroyed Kura server in that region, and
    * an account with no such profiles — or without runner access — should
      have none there.

  Runner Profiles are auto-created for every account, so profiles identify the
  platform whose cache is needed rather than providing a second entitlement.
  The reconciler evaluates the same runner-availability function as dispatch,
  making co-located caching an automatic part of the runner product. A global
  runner rule therefore provisions caches for every eligible account, while an
  account whose runner access is removed has its cache torn down.

  In production, an actor-only runner flag narrows the account query before the
  final availability check. Broad gates still evaluate every eligible account.
  Both steps use one flag snapshot so a concurrent flag update cannot produce a
  mixed cohort within a reconciliation tick.

  The platform match keeps the node next to the fleet it serves: a region
  pinned beside the Scaleway Mac mini fleet provisions only for accounts with
  macOS profiles, and an account that drops its last macOS profile frees that
  node even while its Linux profiles keep a node in a Linux-serving region.

  This runs inside `Tuist.Kura.Reconciler`'s tick rather than on its own
  cron, so it shares the same cadence and self-heals after a BEAM
  restart: enabling runners for an account provisions the node on the next
  tick; disabling them tears it down. It is a no-op unless a private region is
  available in this runtime (via `TUIST_KURA_AVAILABLE_REGIONS`) and a Kura
  runtime image tag is configured, so non-managed and not-yet-wired
  environments stay inert.

  Provisioning the node does not, by itself, route any traffic to it —
  `Tuist.Kura.runner_cache_endpoint_url/2` only returns a URL once the
  node is `:active`, and runner dispatch resolves that lazily.
  """

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias Tuist.Kura
  alias Tuist.Kura.Deployment
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server
  alias Tuist.Repo
  alias Tuist.Runners.Profile

  require Logger

  @retry_backoff_seconds [60, 300, 900, 3600]

  @doc """
  Converges runner-cache nodes with runner availability. Safe to call on every
  reconciler tick; returns `:ok`.
  """
  def reconcile do
    case runner_cache_regions() do
      [] ->
        :ok

      regions ->
        account_ids = runner_enabled_account_ids(regions)
        Enum.each(regions, &reconcile_region(&1, account_ids))
    end

    :ok
  end

  defp reconcile_region(%Regions{id: region_id} = region, account_ids) do
    # Tear down first so an account that flips runners off frees its node
    # even when no image tag is configured to provision new ones.
    Enum.each(nodes_to_tear_down(region, account_ids), &tear_down/1)

    case image_tag() do
      nil ->
        :ok

      image_tag ->
        Enum.each(accounts_needing_node(region, account_ids), &provision(&1, region_id, image_tag))
        # A node that failed before its first successful deployment
        # (transient apiserver error, missing CRD field, ...) would
        # otherwise strand its account forever: the server row exists,
        # so provisioning never re-runs, and nothing else retries
        # failed servers. Self-heal them on the same cadence.
        Enum.each(nodes_to_retry(region_id, image_tag), &retry(&1, image_tag))
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

  defp runner_enabled_account_ids(regions) do
    availability = runner_availability()

    platforms =
      regions
      |> Enum.flat_map(&region_platforms/1)
      |> Enum.uniq()

    profile_exists =
      from(p in Profile,
        where: p.account_id == parent_as(:account).id,
        where: p.platform in ^platforms,
        select: 1
      )

    query =
      from(a in Account,
        as: :account,
        where: exists(profile_exists),
        order_by: [asc: a.id],
        select: struct(a, [:id])
      )

    query
    |> scope_runner_candidates(availability)
    |> Repo.all()
    |> Enum.filter(&runner_enabled?(&1, availability))
    |> MapSet.new(& &1.id)
  end

  defp runner_availability do
    if Environment.prod?() do
      case FunWithFlags.get_flag(:runners) do
        nil ->
          %FunWithFlags.Flag{name: :runners, gates: []}

        {:error, reason} ->
          raise "could not load runner availability: #{inspect(reason)}"

        %FunWithFlags.Flag{} = flag ->
          flag
      end
    else
      :all
    end
  end

  defp scope_runner_candidates(query, :all), do: query

  defp scope_runner_candidates(query, %FunWithFlags.Flag{gates: gates}) do
    if Enum.any?(gates, &broad_runner_gate?/1) do
      query
    else
      account_ids = enabled_account_actor_ids(gates)
      where(query, [account: account], account.id in ^MapSet.to_list(account_ids))
    end
  end

  defp runner_enabled?(_account, :all), do: true
  defp runner_enabled?(account, flag), do: FeatureFlags.runners_enabled?(account, flag)

  defp broad_runner_gate?(%FunWithFlags.Gate{type: :boolean, enabled: true}), do: true
  defp broad_runner_gate?(%FunWithFlags.Gate{type: :group, enabled: true}), do: true
  defp broad_runner_gate?(%FunWithFlags.Gate{type: :percentage_of_time}), do: true
  defp broad_runner_gate?(%FunWithFlags.Gate{type: :percentage_of_actors}), do: true
  defp broad_runner_gate?(_gate), do: false

  defp enabled_account_actor_ids(gates) do
    Enum.reduce(gates, MapSet.new(), fn
      %FunWithFlags.Gate{type: :actor, for: "account:" <> account_id, enabled: true}, account_ids ->
        case Integer.parse(account_id) do
          {parsed_id, ""} -> MapSet.put(account_ids, parsed_id)
          _ -> account_ids
        end

      _gate, account_ids ->
        account_ids
    end)
  end

  defp accounts_needing_node(%Regions{id: region_id} = region, account_ids) do
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

    Repo.all(
      from(a in Account,
        as: :account,
        where: a.id in ^MapSet.to_list(account_ids),
        where: exists(profile_exists),
        where: not exists(server_exists),
        order_by: [asc: a.id],
        select: a.id
      )
    )
  end

  defp nodes_to_tear_down(%Regions{id: region_id} = region, account_ids) do
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

    cohort_ids = MapSet.to_list(account_ids)

    outside_cohort =
      Repo.all(
        from(s in Server,
          as: :server,
          where: s.region == ^region_id,
          where: s.status not in [:destroying, :destroyed],
          where: exists(profile_exists),
          where: s.account_id not in ^cohort_ids,
          select: s
        )
      )

    Enum.uniq_by(no_profiles ++ outside_cohort, & &1.id)
  end

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
  defp nodes_to_retry(region_id, image_tag) do
    servers = failed_first_deploy_servers(region_id)
    failure_histories = retry_failure_histories(servers, image_tag)

    Enum.filter(servers, &retry_due?(&1, Map.get(failure_histories, &1.id, [])))
  end

  defp failed_first_deploy_servers(region_id) do
    Repo.all(
      from(s in Server,
        where: s.region == ^region_id,
        where: s.status == :failed,
        where: is_nil(s.current_image_tag),
        select: s
      )
    )
  end

  defp retry_failure_histories([], _image_tag), do: %{}

  defp retry_failure_histories(servers, image_tag) do
    server_ids = Enum.map(servers, & &1.id)

    ranked_failures =
      from(d in Deployment,
        where: d.kura_server_id in ^server_ids,
        where: d.image_tag == ^image_tag,
        where: d.status == :failed,
        windows: [
          per_server: [
            partition_by: d.kura_server_id,
            order_by: [desc: d.finished_at, desc: d.inserted_at, desc: d.id]
          ]
        ],
        select: %{
          finished_at: d.finished_at,
          rank: over(row_number(), :per_server),
          server_id: d.kura_server_id
        }
      )

    ranked_failures
    |> subquery()
    |> where([failure], failure.rank <= ^length(@retry_backoff_seconds))
    |> order_by([failure], asc: failure.server_id, asc: failure.rank)
    |> select([failure], {failure.server_id, failure.finished_at})
    |> Repo.all()
    |> Enum.group_by(fn {server_id, _finished_at} -> server_id end, fn {_server_id, finished_at} -> finished_at end)
  end

  defp retry_due?(%Server{} = server, failures) do
    case failures do
      [] ->
        true

      [nil | _] ->
        false

      [last_failed_at | _] ->
        delay = retry_delay_seconds(server.id, length(failures))
        retry_at = DateTime.add(last_failed_at, delay, :second)
        DateTime.compare(DateTime.utc_now(), retry_at) != :lt
    end
  end

  defp retry_delay_seconds(server_id, failure_count) do
    base_delay = Enum.at(@retry_backoff_seconds, failure_count - 1)
    jitter_window = div(base_delay, 10)
    jitter = :erlang.phash2(server_id, jitter_window * 2 + 1) - jitter_window
    min(base_delay + jitter, List.last(@retry_backoff_seconds))
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
