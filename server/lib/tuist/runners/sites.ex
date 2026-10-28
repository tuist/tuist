defmodule Tuist.Runners.Sites do
  @moduledoc """
  Where rack runners are, and whether the rack can serve its pools.

  A rack pool spans every site whose runners are on, so a queued job is bound
  to its Xcode and shape, not to a site: the Node of the runner that claims it
  decides the site (`claim_site/2`). A runner may pass over a job for a short
  while to leave it to the site where its account's runner cache is warm
  (`prefer_cache_site/3`).

  A pool is down when no Node of its fleet, at any site, is Ready, schedulable
  and large enough for its guest (`:no_capacity`), or when its oldest queued
  job has outwaited the stall bound while nothing in the fleet held or took a
  claim (`:stalled`). The bound is longer while no such Node holds the pool's
  golden image, since a cold pull is not an outage. A busy pool is up, and so
  is one whose cluster state cannot be read.
  """

  import Ecto.Query

  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.Kubernetes.Client
  alias Tuist.Kubernetes.Quantity
  alias Tuist.Kura
  alias Tuist.Repo
  alias Tuist.Runners.Catalog
  alias Tuist.Runners.Claim
  alias Tuist.Runners.WorkflowJob

  require Logger

  @fleet_label "tuist.dev/fleet"
  @golden_label_prefix "tuist.dev/golden-"
  @site_label "node.cluster.x-k8s.io/rack-site"
  @warm_stall_seconds 600
  @cold_stall_seconds 1_800
  @status_ttl_ms 30_000
  @read_timeout to_timeout(second: 5)
  @node_site_ttl_ms to_timeout(minute: 10)
  @cache_site_grace_seconds 60

  def available?(site_pool) when is_binary(site_pool) do
    status =
      KeyValueStore.get_or_update([__MODULE__, :status, site_pool], [cache: cache_name(), ttl: @status_ttl_ms], fn ->
        status(site_pool)
      end)

    status == :up
  end

  def status(site_pool) when is_binary(site_pool) do
    with {:ok, %{"spec" => %{"fleetSelector" => fleet} = spec}} when is_binary(fleet) <-
           Client.get_runner_pool(Environment.runners_namespace(), site_pool),
         {:ok, %{"items" => nodes}} when is_list(nodes) <-
           Client.list_nodes("#{@fleet_label}=#{fleet}", timeout: @read_timeout) do
      case Enum.filter(nodes, &fits?(&1, spec)) do
        [] -> {:down, :no_capacity}
        eligible -> if stalled?(site_pool, warm?(eligible, spec)), do: {:down, :stalled}, else: :up
      end
    else
      other ->
        Logger.warning("runners: could not read site pool state; keeping it up",
          fleet: site_pool,
          reason: inspect(other)
        )

        :up
    end
  end

  def cache_name, do: :tuist

  @doc """
  The site a runner of `fleet_name` on `node_name` claims at: the Node's
  `node.cluster.x-k8s.io/rack-site` label, else the pool's site
  (`Catalog.fleet_site/1`), which is also the answer while the Node cannot be
  read. A host lent to another env registers in that env's cluster without the
  label. `nil` for a pool that is not racked at a site, without reading the
  Node.
  """
  def claim_site(fleet_name, node_name) do
    case Catalog.fleet_site(fleet_name) do
      nil -> nil
      pool_site -> node_site(node_name) || pool_site
    end
  end

  defp node_site(node_name) when is_binary(node_name) and node_name != "" do
    [__MODULE__, :node_site, node_name]
    |> KeyValueStore.get_or_update([cache: cache_name(), ttl: @node_site_ttl_ms, cache_errors: false], fn ->
      case Client.get_node(node_name, timeout: @read_timeout) do
        {:ok, node} -> {:ok, get_in(node, ["metadata", "labels", @site_label])}
        other -> {:error, other}
      end
    end)
    |> case do
      {:ok, site} when is_binary(site) and site != "" ->
        site

      {:ok, _no_label} ->
        nil

      {:error, reason} ->
        Logger.warning("runners: could not read the claiming Node's site; using its pool's",
          node: node_name,
          reason: inspect(reason)
        )

        nil
    end
  end

  defp node_site(_node_name), do: nil

  @doc """
  Drops from `candidates` the jobs a runner at `site` leaves, for now, to the
  site where their account's runner cache is warm: the account has a runner
  cache at another site and none at `site` (`Kura.runner_cache_elsewhere/2`),
  and the job has queued for less than #{@cache_site_grace_seconds} seconds.
  While that site has an idle runner it takes the job first. While it is busy
  or dark the job runs here once the grace has passed, so no job waits longer
  than that for its cache. With no site, or one site, nothing is dropped.
  """
  def prefer_cache_site(candidates, site, now \\ DateTime.utc_now())

  def prefer_cache_site([_ | _] = candidates, site, now) when is_binary(site) do
    elsewhere =
      candidates
      |> Enum.map(& &1.account_id)
      |> Enum.uniq()
      |> Kura.runner_cache_elsewhere(site)

    if MapSet.size(elsewhere) == 0 do
      candidates
    else
      waited_since = DateTime.add(now, -@cache_site_grace_seconds, :second)

      Enum.reject(candidates, fn candidate ->
        MapSet.member?(elsewhere, candidate.account_id) and within_grace?(candidate, waited_since)
      end)
    end
  end

  def prefer_cache_site(candidates, _site, _now), do: candidates

  defp within_grace?(%{enqueued_at: %DateTime{} = enqueued_at}, waited_since),
    do: DateTime.after?(enqueued_at, waited_since)

  defp within_grace?(_candidate, _waited_since), do: false

  defp fits?(node, spec) do
    ready?(node) and get_in(node, ["spec", "unschedulable"]) != true and
      allocatable(node, "cpu", 1000) >= Map.get(spec, "podCPUMilli", 0) and
      allocatable(node, "memory", 1) >= Map.get(spec, "podMemoryMB", 0) * 1024 * 1024
  end

  defp ready?(%{"status" => %{"conditions" => conditions}}) when is_list(conditions) do
    Enum.any?(conditions, &match?(%{"type" => "Ready", "status" => "True"}, &1))
  end

  defp ready?(_node), do: false

  defp allocatable(node, resource, scale) do
    node |> get_in(["status", "allocatable", resource]) |> Quantity.parse(scale) || 0
  end

  defp warm?(nodes, %{"image" => image}) when is_binary(image) do
    label = @golden_label_prefix <> (:sha256 |> :crypto.hash(image) |> binary_part(0, 8) |> Base.encode16(case: :lower))
    Enum.any?(nodes, &(get_in(&1, ["metadata", "labels", label]) == "true"))
  end

  defp warm?(_nodes, _spec), do: false

  defp stalled?(site_pool, warm?) do
    since = DateTime.add(DateTime.utc_now(), -if(warm?, do: @warm_stall_seconds, else: @cold_stall_seconds), :second)
    site_pools = pools_at_site(site_pool)

    Repo.exists?(
      from(j in WorkflowJob, where: j.fleet_name == ^site_pool and j.status == "queued" and j.enqueued_at < ^since)
    ) and
      not Repo.exists?(from(c in Claim, where: c.fleet_name in ^site_pools)) and
      not Repo.exists?(from(j in WorkflowJob, where: j.fleet_name in ^site_pools and j.claimed_at >= ^since))
  end

  defp pools_at_site(site_pool) do
    site_pools = Environment.runners_site_pools()

    case Map.fetch(site_pools, site_pool) do
      {:ok, %{site: site}} -> for {pool, %{site: ^site}} <- site_pools, do: pool
      :error -> [site_pool]
    end
  end
end
