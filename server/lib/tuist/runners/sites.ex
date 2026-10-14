defmodule Tuist.Runners.Sites do
  @moduledoc """
  Whether a site can serve the jobs routed to one of its catalog pools. A pool
  is down when no Node of its fleet is Ready, schedulable and large enough for
  its guest (`:no_capacity`), or when its oldest queued job has outwaited the
  stall bound while nothing at the site held or took a claim (`:stalled`). The
  bound is longer while no such Node holds the pool's golden image, since a
  cold pull is not an outage. A busy site is up, and so is one whose cluster
  state cannot be read.
  """

  import Ecto.Query

  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.Kubernetes.Client
  alias Tuist.Kubernetes.Quantity
  alias Tuist.Repo
  alias Tuist.Runners.Claim
  alias Tuist.Runners.WorkflowJob

  require Logger

  @fleet_label "tuist.dev/fleet"
  @golden_label_prefix "tuist.dev/golden-"
  @warm_stall_seconds 600
  @cold_stall_seconds 1_800
  @status_ttl_ms 30_000
  @read_timeout to_timeout(second: 5)

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
