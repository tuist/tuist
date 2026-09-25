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

  The list is the fleet's demand, most imminent first: the volumes of its queued
  jobs, then those of the jobs it ran most over the last day. Volumes whose
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
         :macos <- Catalog.fleet_platform(fleet) do
      %{masters: resident, repository_volumes?: repository_volumes?} =
        VolumeAffinities.cache_volumes_from_node_labels(labels)

      repository_volumes? = repository_volumes? and FeatureFlags.runner_cache_volumes_per_repository_enabled?()

      fleet
      |> demand()
      |> Stream.uniq_by(&{&1.account_id, Map.get(&1, :repository)})
      |> Stream.map(&volume_to_prefetch(&1, resident, repository_volumes?))
      |> Stream.reject(&is_nil/1)
      |> Stream.uniq_by(&{&1.account_id, &1.volume})
      |> Enum.take(@limit)
    else
      _ -> []
    end
  end

  defp demand(fleet) do
    queued =
      case Jobs.pick_queued_top_k(fleet, [], [], [], @queued_candidates) do
        {:ok, candidates} -> candidates
        {:error, :empty} -> []
      end

    since = DateTime.add(DateTime.utc_now(), -@recent_window_seconds, :second)
    Stream.concat(queued, RunnerSessions.recent_demand(fleet, since, @recent_candidates))
  end

  # The volume a job would materialize from on this Node, as dispatch resolves
  # it: its repository's when the Node reads repository volumes, otherwise the
  # account's. Nil when the Node already holds it or nothing is published.
  defp volume_to_prefetch(%{account_id: account_id} = job, resident, repository_volumes?) do
    account_volume = VolumeHeads.reserved_tuist_cache()

    volumes =
      if repository_volumes? do
        [VolumeHeads.volume_name_for_repository(Map.get(job, :repository)), account_volume]
      else
        [account_volume]
      end

    Enum.reduce_while(Enum.uniq(volumes), nil, fn volume, nil ->
      cond do
        MapSet.member?(resident, {account_id, volume}) ->
          {:halt, nil}

        head = Runners.host_volume_head(account_id, volume) ->
          {:halt, Map.merge(head, %{account_id: account_id, volume: volume})}

        true ->
          {:cont, nil}
      end
    end)
  end
end
