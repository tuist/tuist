defmodule Tuist.Runners.VolumePrefetch do
  @moduledoc """
  Which custom cache-volume HEADs a macOS runner host should download before a
  job for them lands on it.

  The host asks here while it is idle, as the host itself rather than through a
  guest: the answer carries download URLs for every account on the fleet, which
  a guest running a customer's job must never see. The host authenticates with a
  token for its own per-machine `tart-kubelet-<machine>` ServiceAccount, whose
  name is its Node's, so it can only ask about its own fleet.

  The list names the saved HEADs of the custom volumes jobs used on the Node's
  host class over the last day, for every Node of the class: dispatch cannot
  know which custom volumes a queued job will attach, so it cannot steer the job
  to a Node holding them. The host downloads these only into free space.
  """
  alias Tuist.Environment
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners.CacheVolumes
  alias Tuist.Runners.Catalog

  @host_service_account_prefix "tart-kubelet-"
  @fleet_label "tuist.dev/fleet"
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
         true <- macos_fleet?(fleet),
         {:ok, peer_names} <- class_peers(node, fleet),
         true <- node_name in peer_names do
      since = DateTime.add(DateTime.utc_now(), -@recent_window_seconds, :second)
      CacheVolumes.recent_macos_heads(peer_names, since, @limit)
    else
      _ -> []
    end
  end

  # The Node's `tuist.dev/fleet` label is its CAPI fleet (for example
  # `tuist-tuist-runners-fleet`), shared by every SKU group in it. It is a macOS
  # fleet when a macOS RunnerPool's `fleetSelector` is that label, the same match
  # the scheduler makes.
  defp macos_fleet?(fleet) do
    case K8sClient.list_runner_pools(Environment.runners_namespace()) do
      {:ok, pools} ->
        Enum.any?(pools, fn pool ->
          name = get_in(pool, ["metadata", "name"])

          get_in(pool, ["spec", "fleetSelector"]) == fleet and is_binary(name) and
            Catalog.fleet_platform(name) == :macos
        end)

      {:error, _reason} ->
        false
    end
  end

  # The Nodes of the fleet in the same host class as `node`, itself included.
  # SKU groups of one fleet share its label, and the Node carries nothing naming
  # its group, but each class advertises its own capacity (an M2-L 8 CPU and
  # 14 GiB, an M4-XL 12 CPU and 28 GiB), which decides which jobs land on it.
  defp class_peers(node, fleet) do
    class = node_class(node)

    case K8sClient.list_nodes("#{@fleet_label}=#{fleet}") do
      {:ok, %{"items" => items}} ->
        names =
          for peer <- items,
              node_class(peer) == class,
              name = get_in(peer, ["metadata", "name"]),
              is_binary(name),
              do: name

        {:ok, names}

      _ ->
        :error
    end
  end

  defp node_class(node) do
    {get_in(node, ["status", "capacity", "cpu"]), get_in(node, ["status", "capacity", "memory"])}
  end
end
