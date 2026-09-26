defmodule Tuist.Runners.VolumePrefetch do
  @moduledoc """
  Which cache-volume masters a macOS runner host should download before a job
  for them lands on it.

  A host otherwise obtains a master only after a job for the volume has run on
  it, and that job starts cold. Its converge worker asks here while it is idle,
  as the host itself rather than through a guest: the answer carries download
  URLs for every account on the fleet, which a guest running a customer's job
  must never see. The host authenticates with a token for its own per-machine
  `tart-kubelet-<machine>` ServiceAccount, whose name is its Node's, so it can
  only ask about its own fleet.

  The list is the demand of the RunnerPools that schedule onto the Node, most
  imminent first: the volumes of their queued jobs, then those of the jobs they
  ran most over the last day. Volumes whose
  master the Node already advertises are left out, because the jobs that land
  there keep them current. A repository volume that has published no master yet
  falls back to its account's `tuist-cache` master, which the host seeds a new
  repository volume from. The host decides what it can keep.
  """
  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners
  alias Tuist.Runners.Catalog
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.RunnerSessions
  alias Tuist.Runners.VolumeAffinities
  alias Tuist.Runners.VolumeHeads

  @host_service_account_prefix "tart-kubelet-"
  @fleet_label "tuist.dev/fleet"
  @queued_candidates 20
  @recent_candidates 10
  @recent_window_seconds 24 * 60 * 60
  @limit 8

  @doc """
  The Node a runner host's ServiceAccount identifies, or `:error` for any other
  ServiceAccount.
  """
  def node_for_service_account(namespace, name) when is_binary(namespace) and is_binary(name) do
    with true <- namespace == Environment.runner_host_identity_namespace(),
         @host_service_account_prefix <> node_name when node_name != "" <- name do
      {:ok, node_name}
    else
      _ -> :error
    end
  end

  def node_for_service_account(_namespace, _name), do: :error

  @doc """
  The HEADs `node_name` should hold, most wanted first, each with a presigned
  download URL. Empty for a Node that is not in a macOS fleet.
  """
  def for_node(node_name) do
    with {:ok, node} <- K8sClient.get_node(node_name),
         labels when is_map(labels) <- get_in(node, ["metadata", "labels"]),
         fleet when is_binary(fleet) <- labels[@fleet_label],
         [_ | _] = pools <- macos_pools_scheduling_onto(fleet),
         {:ok, peers} <- class_peers(node, fleet),
         true <- Enum.any?(peers, &(&1.name == node_name)) do
      %{repository_volumes?: repository_volumes?} = VolumeAffinities.cache_volumes_from_node_labels(labels)
      repository_volumes? = repository_volumes? and FeatureFlags.runner_cache_volumes_per_repository_enabled?()

      context = %{
        node_name: node_name,
        peer_names: Enum.map(peers, & &1.name),
        held_in_class: Enum.reduce(peers, MapSet.new(), &MapSet.union(&1.masters, &2)),
        repository_volumes?: repository_volumes?
      }

      pools
      |> demand(context.peer_names)
      |> Stream.uniq_by(&{&1.account_id, Map.get(&1, :repository)})
      |> Stream.map(&volume_to_prefetch(&1, context))
      |> Stream.reject(&is_nil/1)
      |> Stream.uniq_by(&{&1.account_id, &1.volume})
      |> Enum.take(@limit)
    else
      _ -> []
    end
  end

  # The Node's `tuist.dev/fleet` label is its CAPI fleet (for example
  # `tuist-tuist-runners-fleet`), shared by every SKU group in it. Jobs are queued
  # and recorded under RunnerPool names instead, and the pools that run on this
  # Node are the macOS ones whose `fleetSelector` is that label, the same match
  # the scheduler makes.
  defp macos_pools_scheduling_onto(fleet) do
    case K8sClient.list_runner_pools(Environment.runners_namespace()) do
      {:ok, pools} ->
        for pool <- pools,
            get_in(pool, ["spec", "fleetSelector"]) == fleet,
            name = get_in(pool, ["metadata", "name"]),
            is_binary(name) and Catalog.fleet_platform(name) == :macos,
            do: name

      {:error, _reason} ->
        []
    end
  end

  # The Nodes of the fleet in the same host class as `node`, itself included,
  # with the masters each advertises. SKU groups of one fleet share its label,
  # and the Node carries nothing naming its group, but each class advertises its
  # own capacity (an M2-L 8 CPU and 14 GiB, an M4-XL 12 CPU and 28 GiB), which
  # is what decides how many masters it can keep and which jobs land on it.
  defp class_peers(node, fleet) do
    class = node_class(node)

    case K8sClient.list_nodes("#{@fleet_label}=#{fleet}") do
      {:ok, %{"items" => items}} ->
        {:ok,
         for peer <- items,
             node_class(peer) == class,
             name = get_in(peer, ["metadata", "name"]),
             is_binary(name) do
           labels = get_in(peer, ["metadata", "labels"]) || %{}
           %{name: name, masters: VolumeAffinities.cache_volumes_from_node_labels(labels).masters}
         end}

      _ ->
        :error
    end
  end

  defp node_class(node) do
    {get_in(node, ["status", "capacity", "cpu"]), get_in(node, ["status", "capacity", "memory"])}
  end

  # Queued jobs may land on any class, so they count wherever they are queued.
  # Recent demand counts only the jobs that ran on this class: an account whose
  # jobs run on the M4-XL hosts is not worth a copy on every M2-L.
  defp demand(pools, peer_names) do
    queued =
      pools
      |> Enum.flat_map(fn pool ->
        case Jobs.pick_queued_top_k(pool, [], [], [], @queued_candidates) do
          {:ok, candidates} -> candidates
          {:error, :empty} -> []
        end
      end)
      |> Enum.sort_by(& &1.enqueued_at, DateTime)
      |> Enum.take(@queued_candidates)

    since = DateTime.add(DateTime.utc_now(), -@recent_window_seconds, :second)
    Stream.concat(queued, RunnerSessions.recent_demand(pools, since, @recent_candidates, node_names: peer_names))
  end

  # The volume a job would materialize from on this Node, as dispatch resolves
  # it: its repository's when the Node reads repository volumes, otherwise the
  # account's. Nil when a Node of this class already holds it, when another Node
  # of the class is the one to fetch it, or when nothing is published.
  #
  # One copy per class is the prefetch's job. Dispatch prefers a Node holding
  # the master, so that copy takes the account's jobs, and each Node a job lands
  # on without it converges its own copy afterwards. Every idle Node fetching the
  # same master at once would spend the class's disk and bandwidth on copies
  # nothing reads.
  defp volume_to_prefetch(%{account_id: account_id} = job, context) do
    account_volume = VolumeHeads.reserved_tuist_cache()

    volumes =
      if context.repository_volumes? do
        [VolumeHeads.volume_name_for_repository(Map.get(job, :repository)), account_volume]
      else
        [account_volume]
      end

    Enum.reduce_while(Enum.uniq(volumes), nil, fn volume, nil ->
      cond do
        MapSet.member?(context.held_in_class, {account_id, volume}) ->
          {:halt, nil}

        not assigned_here?(account_id, volume, context) ->
          {:halt, nil}

        head = Runners.host_volume_head(account_id, volume) ->
          {:halt, Map.merge(head, %{account_id: account_id, volume: volume})}

        true ->
          {:cont, nil}
      end
    end)
  end

  # Rendezvous hashing: every server replica picks the same Node of the class for
  # a volume, without coordinating, and a Node joining or leaving moves only the
  # volumes it wins or held.
  defp assigned_here?(account_id, volume, %{node_name: node_name, peer_names: peer_names}) do
    Enum.max_by(peer_names, &:erlang.phash2({account_id, volume, &1})) == node_name
  end
end
