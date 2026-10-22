defmodule Tuist.Runners.VolumePrefetch do
  @moduledoc """
  Which custom cache-volume HEADs a runner host should download before a job for
  them lands on it.

  The host asks here as the host itself, never through a guest: the answer names
  saved HEADs of every account on the fleet, which a guest running a customer's
  job must never see. A macOS host authenticates with a token for its own
  per-machine `tart-kubelet-<machine>` ServiceAccount, whose name is its Node's,
  so it can only ask about its own fleet. A Linux host's cache agent uses the
  agent ServiceAccount every Linux Node shares, which can already download any
  HEAD by its use, and names its Node as in its other requests.

  The list names the saved HEADs of the platform's custom volumes that jobs used
  on the Node's peers, for every peer (`CacheVolumes.prefetch_heads/3`): first
  the volumes runs keep reusing and have left idle, so the account's next working
  day starts warm, then the volumes used in the last day. Dispatch hands a queued
  job to whichever host polls first, and an account's first job of the day goes
  to any idle runner, so every peer gets the same list. Peers are the Nodes of a
  macOS host class, or every Node of a Linux fleet, whose job shapes share its
  Nodes. Hosts download these only into free space.
  """
  alias Tuist.Environment
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners.CacheVolumes
  alias Tuist.Runners.Catalog

  @host_service_account_prefix "tart-kubelet-"
  @fleet_label "tuist.dev/fleet"

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
  The HEADs `node_name` should hold, most wanted first, each with the reason it
  is listed for. Empty for a Node that is not in a fleet of `platform`
  (`:macos` or `:linux`).
  """
  def for_node(node_name, platform) when platform in [:macos, :linux] do
    with {:ok, node} <- K8sClient.get_node(node_name),
         labels when is_map(labels) <- get_in(node, ["metadata", "labels"]),
         fleet when is_binary(fleet) <- labels[@fleet_label],
         true <- platform_fleet?(fleet, platform),
         {:ok, peer_names} <- peers(node, fleet, platform),
         true <- node_name in peer_names do
      CacheVolumes.prefetch_heads(Atom.to_string(platform), peer_names, DateTime.utc_now())
    else
      _ -> []
    end
  end

  # The Node's `tuist.dev/fleet` label is its CAPI fleet (for example
  # `tuist-tuist-runners-fleet`), shared by every SKU group in it. It is a fleet
  # of a platform when a RunnerPool of that platform has it as its
  # `fleetSelector`, the same match the scheduler makes.
  defp platform_fleet?(fleet, platform) do
    case K8sClient.list_runner_pools(Environment.runners_namespace()) do
      {:ok, pools} ->
        Enum.any?(pools, fn pool ->
          name = get_in(pool, ["metadata", "name"])

          get_in(pool, ["spec", "fleetSelector"]) == fleet and is_binary(name) and
            Catalog.fleet_platform(name) == platform
        end)

      {:error, _reason} ->
        false
    end
  end

  # The Nodes of a Linux fleet, or those of a macOS fleet in the same host class as
  # `node`, itself included. SKU groups of one fleet share its label, and the Node carries nothing naming
  # its group, but each class advertises its own capacity (an M2-L 8 CPU and
  # 14 GiB, an M4-XL 12 CPU and 28 GiB), which decides which jobs land on it.
  defp peers(node, fleet, platform) do
    class = node_class(node)

    case K8sClient.list_nodes("#{@fleet_label}=#{fleet}") do
      {:ok, %{"items" => items}} ->
        names =
          for peer <- items,
              platform == :linux or node_class(peer) == class,
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
