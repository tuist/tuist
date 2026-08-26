defmodule Tuist.Kura.Capacity do
  @moduledoc """
  How full a Kura region is, read from the cluster.

  Admission is not decided here. Every cache pod requests its claim's worth of
  `ephemeral-storage`, so the scheduler bin-packs instances against each node's
  disk and simply declines to place one that does not fit. That is exact, per
  node, and cannot drift from what the cluster actually holds -- which a
  forecast built from a quota table in this repo did, by a factor of about
  three, until it was replaced by this.

  What is left is the question the scheduler cannot answer: whether the region
  as a whole is tight enough that Air's inactivity window should shorten from
  90 complete days to 60, so archival starts making room before provisioning
  starts being declined. That is a region-level reading, and it is taken from
  the same numbers the scheduler places against -- the ephemeral-storage the
  region's pods have reserved, against what its Ready nodes make allocatable.

  Reservations rather than live usage on purpose. A freshly provisioned
  instance holds almost nothing and fills over days, so a region full of new
  instances reads as empty right up to the moment they all fill at once. What
  the region has promised is the thing that has to fit.

  A region whose nodes cannot be read is unknown: pressure archival never runs,
  so the 90-day target holds. The scheduler still refuses to overfill a node in
  the meantime, because that has never depended on this module.
  """

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.KeyValueStore
  alias Tuist.Kubernetes.Client
  alias Tuist.Kura.AccountPolicies
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server
  alias Tuist.Repo

  @gib 1024 * 1024 * 1024

  # Share of a region's allocatable disk that may be reserved before Air's
  # window shortens. Below 1 on purpose: pressure has to arrive while there is
  # still room to place instances, so archival creates space ahead of the
  # scheduler starting to decline. It also leaves the margin kubelet needs --
  # it evicts at `imagefs.available<15%`, on the same disk the cache ring
  # lives on, and an eviction takes the node's whole region with it.
  @pressure_fraction 0.85

  # Replicas an instance runs when its region declares none, matching the
  # kura-controller's own default. Guessing lower would understate what an
  # instance reserves, which is the direction that overcommits.
  @default_replicas 3

  # Reserved by an instance whose region declares no claim size, matching the
  # controller's own fallback.
  @default_claim_gib 200

  @namespace "kura"
  @managed_by_selector "app.kubernetes.io/managed-by=kura-controller"

  @doc """
  Bytes of the region's disk one instance reserves, across every replica.
  """
  def resident_bytes(region, server), do: resident_gib(region, server) * @gib

  @doc """
  Gibibytes of the region's disk one instance reserves.

  Every replica requests the instance's claim size, and the bare-metal regions
  co-locate an account's replicas on one box, so two replicas reserve two
  claims on the same disk. The claim is a property of the instance, sized from
  its account's plan where the region asks for that, so an Air instance
  reserves less than an Enterprise one and the two cannot be counted with a
  single per-region figure. The replica count stays a property of the region.
  An instance that carries no claim of its own falls back to what its region
  declares.
  """
  def resident_gib(%Regions{} = region, %Server{} = server), do: claim_gib(region, server) * replicas(region)

  # Through the same quantity parser the node and pod readings use, not a
  # Gi-only one. A claim is persisted in any unit Kubernetes accepts, and one
  # written as `1Ti` renders correctly on the manifest while a narrower parser
  # reads it as unparseable and silently substitutes the region's claim — an
  # instance counted at a fraction of what it reserves, in the direction that
  # overcommits.
  defp claim_gib(%Regions{} = region, %Server{storage_claim_size: size}) when is_binary(size) do
    case parse_quantity(size) do
      bytes when is_integer(bytes) and bytes > 0 -> div(bytes, @gib)
      _ -> claim_gib(region)
    end
  end

  # A region that sizes per plan declares no claim of its own, so an instance
  # carrying none is read the way the manifest renders it rather than at the
  # controller's 200Gi fallback, which would overstate it by an order of
  # magnitude. The archival loop preloads the account this reads.
  defp claim_gib(%Regions{} = region, %Server{account: %Account{} = account}) do
    if Regions.storage_governed?(region) do
      case parse_quantity(Regions.storage_profile(AccountPolicies.sizing_plan(account)).claim_size) do
        bytes when is_integer(bytes) and bytes > 0 -> div(bytes, @gib)
        _ -> claim_gib(region)
      end
    else
      claim_gib(region)
    end
  end

  defp claim_gib(%Regions{} = region, %Server{}), do: claim_gib(region)

  defp claim_gib(%Regions{provisioner_config: %{storage_size: size}}) when is_binary(size) do
    case parse_quantity(size) do
      bytes when is_integer(bytes) and bytes > 0 -> div(bytes, @gib)
      _ -> @default_claim_gib
    end
  end

  defp claim_gib(%Regions{}), do: @default_claim_gib

  defp replicas(%Regions{provisioner_config: %{replicas: replicas}}) when is_integer(replicas) and replicas > 0,
    do: replicas

  defp replicas(%Regions{}), do: @default_replicas

  @doc """
  Allocatable disk across the region's Ready nodes, in gibibytes, or `nil`
  when it cannot be read.
  """
  def allocatable_gib(region_id) do
    KeyValueStore.get_or_update(
      [__MODULE__, "allocatable_gib", region_id],
      [ttl: to_timeout(minute: 1), locking: true],
      fn -> measure_allocatable_gib(region_id) end
    )
  end

  # Summed from the nodes themselves rather than from a machine count times an
  # assumed size per machine: the regions do not run the same hardware, and an
  # assumed figure is wrong in whichever direction the real boxes differ.
  defp measure_allocatable_gib(region_id) do
    with {:ok, region} <- Regions.fetch(region_id),
         selector when is_binary(selector) <- Regions.node_label_selector(region),
         {:ok, %{"items" => items}} <- Client.list_nodes(selector) do
      items
      |> Enum.filter(&ready?/1)
      |> Enum.map(&allocatable_bytes/1)
      |> Enum.sum()
      |> to_gib()
    else
      _ -> nil
    end
  end

  defp to_gib(0), do: nil
  defp to_gib(bytes), do: trunc(bytes / @gib)

  @doc """
  The egress budget, in Mbit/s, that the region's smallest Ready box advertises
  as `tuist.dev/egress-mbps`, or `nil` when no node advertises one or the
  cluster cannot be read.

  The *smallest*, not the sum and not the largest: this is the number a single
  tenant's floor and ceiling have to fit inside, and a pod lands on one box
  without anybody knowing which in advance. A region can hold boxes of different
  sizes (the budget is declared per machine, as its NIC ceiling minus headroom),
  so the only figure that holds wherever the pod lands is the smallest one on
  offer.

  This is the *only* real bound on a per-account egress override. A region's own
  floor/ceiling pair is a default sized for the fleet, not a statement about what
  the hardware can do, so it must never be used in this number's place.
  """
  def egress_budget_mbps(region_id) do
    KeyValueStore.get_or_update(
      [__MODULE__, "egress_budget_mbps", region_id],
      [ttl: to_timeout(minute: 1), locking: true],
      fn -> measure_egress_budget_mbps(region_id) end
    )
  end

  defp measure_egress_budget_mbps(region_id) do
    with {:ok, region} <- Regions.fetch(region_id),
         selector when is_binary(selector) <- Regions.node_label_selector(region),
         {:ok, %{"items" => items}} <- Client.list_nodes(selector) do
      items
      |> Enum.filter(&ready?/1)
      |> Enum.map(&egress_mbps/1)
      |> Enum.reject(&is_nil/1)
      |> case do
        [] -> nil
        budgets -> Enum.min(budgets)
      end
    else
      _ -> nil
    end
  end

  @doc """
  How much egress the box `account_handle`'s instances in `region_id` sit on can
  hold for that account, and across how many replicas — or `nil` when it has
  none placed there yet, where nothing pins it and `egress_budget_mbps/1` is the
  whole answer.

      %{node:, allocatable_mbps:, available_mbps:, replicas:}

  `available_mbps` is the box less what *other* tenants reserve on it: a rollout
  hands each replica's own reservation in before asking for its replacement, so
  the account is not charged for what it already holds.

  Every replica reserves the floor, and the rollout replaces them one at a time,
  releasing the old value at each step. On the last step the old values are all
  gone, which is what a raise has to fit:

      replicas x floor <= allocatable - other tenants

  Nothing here reads what the replicas hold now. An account mid-rollout holds
  different values on different replicas, so a bound written in terms of them
  answers differently depending on when it is asked.

  Read from the box the account's instance is on -- its replicas are co-located
  there and their volumes pin them to it -- rather than from the region, whose
  other boxes cannot take the pod however much room they have.
  """
  def egress_headroom(region_id, account_handle) when is_binary(account_handle) do
    KeyValueStore.get_or_update(
      [__MODULE__, "egress_headroom", region_id, account_handle],
      [ttl: to_timeout(minute: 1), locking: true],
      fn -> measure_egress_headroom(region_id, account_handle) end
    )
  end

  defp measure_egress_headroom(region_id, account_handle) do
    with {:ok, pods} <- Client.list_pods(@namespace, account_selector(region_id, account_handle)),
         [pod | _] <- Enum.filter(pods, &(pod_node_name(&1) && not terminal?(&1))),
         node = pod_node_name(pod),
         on_box = Enum.filter(pods, &(pod_node_name(&1) == node)),
         {:ok, node_body} <- Client.get_node(node),
         allocatable when is_integer(allocatable) <- egress_mbps(node_body),
         {:ok, reserved} <- box_reserved_mbps(node) do
      own_mbps = on_box |> Enum.map(&pod_egress_mbps/1) |> Enum.sum()

      %{
        node: node,
        allocatable_mbps: allocatable,
        # The account's own reservation is added back: the rollout hands it in
        # before asking for the replacement.
        available_mbps: max(allocatable - (reserved - own_mbps), 0),
        # Raised to what the region declares: a replica between deletion and
        # recreation is in no pod list, and its volume brings it back here.
        replicas: max(length(on_box), declared_replicas(region_id))
      }
    else
      _ -> nil
    end
  end

  # Everything on the box, whoever owns it -- an extended resource is reserved
  # against the node, not against a namespace. There is no API for a node's
  # allocated total, so this is summed the way `kubectl describe node` sums it.
  defp box_reserved_mbps(node) do
    case Client.list_pods_on_node(node) do
      {:ok, pods} ->
        {:ok, pods |> Enum.reject(&terminal?/1) |> Enum.map(&pod_egress_mbps/1) |> Enum.sum()}

      {:error, _reason} = error ->
        error
    end
  end

  # Pods of this account's instance in this region. A box can carry the same
  # account's pods from another region or from a self-hosted deployment, and
  # those are neither its replicas nor its reservation.
  defp account_selector(region_id, account_handle) do
    "#{@managed_by_selector},tuist.dev/region=#{region_id},tuist.dev/account=#{account_handle}"
  end

  defp declared_replicas(region_id) do
    case Regions.fetch(region_id) do
      {:ok, region} -> replicas(region)
      {:error, _reason} -> 1
    end
  end

  defp pod_node_name(%{"spec" => %{"nodeName" => name}}) when is_binary(name) and name != "", do: name
  defp pod_node_name(_pod), do: nil

  defp pod_egress_mbps(%{"spec" => %{"containers" => containers}}) when is_list(containers) do
    Enum.reduce(containers, 0, fn container, total -> total + container_egress_mbps(container) end)
  end

  defp pod_egress_mbps(_pod), do: 0

  defp container_egress_mbps(%{"resources" => %{"requests" => %{"tuist.dev/egress-mbps" => quantity}}}),
    do: parse_quantity(quantity) || 0

  defp container_egress_mbps(_container), do: 0

  defp egress_mbps(%{"status" => %{"allocatable" => %{"tuist.dev/egress-mbps" => quantity}}}) do
    parse_quantity(quantity)
  end

  defp egress_mbps(_node), do: nil

  # A node that is not Ready contributes nothing: its disk is not reachable
  # for scheduling, which a declared machine count could never express.
  defp ready?(%{"status" => %{"conditions" => conditions}}) when is_list(conditions) do
    Enum.any?(conditions, &match?(%{"type" => "Ready", "status" => "True"}, &1))
  end

  defp ready?(_node), do: false

  # `ephemeral-storage` is the filesystem kubelet manages, which on every
  # region in this fleet is the one the cache ring lives on: the bare-metal
  # boxes whose data disk is separate bind-mount `/var/lib/kubelet` onto it,
  # and the rest keep both on `/`.
  defp allocatable_bytes(%{"status" => %{"allocatable" => %{"ephemeral-storage" => quantity}}}) do
    parse_quantity(quantity) || 0
  end

  defp allocatable_bytes(_node), do: 0

  @quantity_suffixes %{
    "" => 1,
    "k" => 1000,
    "M" => 1000 ** 2,
    "G" => 1000 ** 3,
    "T" => 1000 ** 4,
    "Ki" => 1024,
    "Mi" => 1024 ** 2,
    "Gi" => 1024 ** 3,
    "Ti" => 1024 ** 4
  }

  defp parse_quantity(quantity) when is_binary(quantity) do
    case Integer.parse(quantity) do
      {value, suffix} ->
        case Map.fetch(@quantity_suffixes, suffix) do
          {:ok, multiplier} -> value * multiplier
          :error -> nil
        end

      :error ->
        nil
    end
  end

  defp parse_quantity(quantity) when is_integer(quantity), do: quantity
  defp parse_quantity(_quantity), do: nil

  @doc """
  Gibibytes of the region's disk its pods have reserved, or `nil` when the
  cluster cannot be read.

  Read from the pods' own `ephemeral-storage` requests rather than derived
  from this repo's rows: it is the number the scheduler places against, it
  already accounts for replicas and for anything else sharing the region's
  nodes, and it cannot disagree with the cluster the way a parallel model can.
  """
  def reserved_gib(region_id) do
    KeyValueStore.get_or_update(
      [__MODULE__, "reserved_gib", region_id],
      [ttl: to_timeout(minute: 1), locking: true],
      fn -> measure_reserved_gib(region_id) end
    )
  end

  defp measure_reserved_gib(region_id) do
    case Client.list_pods(@namespace, "#{@managed_by_selector},tuist.dev/region=#{region_id}") do
      {:ok, pods} ->
        pods
        |> Enum.reject(&terminal?/1)
        |> Enum.map(&requested_bytes/1)
        |> Enum.sum()
        |> div(@gib)

      {:error, _reason} ->
        nil
    end
  end

  # A pod that has run to completion or been evicted holds no directory, and
  # the scheduler counts neither against the node.
  defp terminal?(%{"status" => %{"phase" => phase}}), do: phase in ["Succeeded", "Failed"]
  defp terminal?(_pod), do: false

  defp requested_bytes(%{"spec" => %{"containers" => containers}}) when is_list(containers) do
    Enum.reduce(containers, 0, fn container, total ->
      total + container_requested_bytes(container)
    end)
  end

  defp requested_bytes(_pod), do: 0

  defp container_requested_bytes(%{"resources" => %{"requests" => %{"ephemeral-storage" => quantity}}}),
    do: parse_quantity(quantity) || 0

  defp container_requested_bytes(_container), do: 0

  @doc """
  Gibibytes a region may reserve before Air's window shortens, or `nil` when
  its nodes cannot be read.
  """
  def pressure_line_gib(region_id) do
    case allocatable_gib(region_id) do
      allocatable when is_integer(allocatable) -> trunc(allocatable * @pressure_fraction)
      _ -> nil
    end
  end

  @doc """
  Whether the region has reserved more of its disk than it may before Air's
  window shortens. Only under that pressure may Air instances be drained at 60
  complete inactive days instead of 90.

  False whenever either side cannot be read, so pressure archival never runs
  uninformed.
  """
  def under_pressure?(region_id) do
    with target when is_integer(target) <- pressure_line_gib(region_id),
         reserved when is_integer(reserved) <- reserved_gib(region_id) do
      reserved > target
    else
      _ -> false
    end
  end

  @doc """
  Region occupancy as `%{reserved_gib:, allocatable_gib:, instances:, ratio:}`,
  for the region occupancy metric. Any of them is `nil` when the cluster
  cannot be read.
  """
  def occupancy(region_id) do
    reserved = reserved_gib(region_id)
    allocatable = allocatable_gib(region_id)

    %{
      reserved_gib: reserved,
      allocatable_gib: allocatable,
      instances: instance_count(region_id),
      ratio: if(reserved && allocatable && allocatable > 0, do: reserved / allocatable)
    }
  end

  # A move leaves two rows for one account; both hold a directory, so both
  # count.
  defp instance_count(region_id) do
    Repo.aggregate(
      from(s in Server,
        where: s.region == ^region_id,
        where: s.status not in [:destroyed, :archived]
      ),
      :count
    )
  end
end
