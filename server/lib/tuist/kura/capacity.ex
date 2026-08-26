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
  none placed there yet (then nothing pins it and `egress_budget_mbps/1` is the
  whole answer).

      %{node:, allocatable_mbps:, available_mbps:, replicas:}

  `available_mbps` is what the box has for *this account*: everything it
  advertises, less what other tenants have reserved on it. It deliberately
  counts the account's own current reservation as available, because a rollout
  releases each replica's before asking for its replacement.

  That is the whole of the bound, and it is simpler than it first looks. Walking
  a floor change through the rollout, with `O` the other tenants and `c_i` what
  each replica holds now:

      step k:  O + k x new + sum(c_i for i > k)  <= allocatable
      step r:  O + r x new                       <= allocatable

  Every step releases one old value and takes one new one, so on the last step
  the old values are all gone and the `c_i` cancel out. A raise tightens the
  constraint at each step, which makes the last one binding:

      replicas x new_floor <= allocatable - other tenants

  What the replicas hold *now* never enters it. That matters: an account caught
  mid-rollout holds different values on different replicas, and any formula
  written in terms of them reports a different bound depending on when it is
  asked.

  Two things this still has to get right:

    * **The box, not the region.** A replica's volume pins it to one node, so a
      roomier sibling box is no help — it is the only node the pod can ever be
      placed on again. Where an account somehow spans boxes, the binding one is
      whichever holds least for it.
    * **Scheduled pods only.** An unscheduled pod holds nothing on a node, so it
      cannot count towards what other tenants have reserved there. It is exactly
      the pod this measurement exists to make room for.
  """
  def egress_headroom(region_id, account_handle) when is_binary(account_handle) do
    with %{nodes: nodes, accounts: accounts} <- egress_placement(region_id),
         %{nodes: [_ | _] = account_nodes, replicas: replicas} <- Map.get(accounts, account_handle),
         {node, available} <- worst_node(account_nodes, nodes) do
      %{
        node: node,
        allocatable_mbps: nodes[node].allocatable_mbps,
        available_mbps: available,
        replicas: max(replicas, declared_replicas(region_id))
      }
    else
      _ -> nil
    end
  end

  # The account's box with the least room for it. Its own reservation on that box
  # is added back, because the rollout hands it in before asking for the
  # replacement -- what bounds the account is the box minus everybody else.
  defp worst_node(account_nodes, nodes) do
    account_nodes
    |> Enum.filter(fn {node, _reserved} -> Map.has_key?(nodes, node) end)
    |> Enum.map(fn {node, reserved} ->
      %{allocatable_mbps: allocatable, reserved_mbps: node_reserved} = nodes[node]
      {node, max(allocatable - (node_reserved - reserved), 0)}
    end)
    |> Enum.min_by(fn {_node, available} -> available end, fn -> nil end)
  end

  # A replica the account is between (deleted, not yet recreated) holds nothing
  # and is not in the pod list, so counting only what is there would divide the
  # box by too few and overstate what a floor may be raised to.
  defp declared_replicas(region_id) do
    case Regions.fetch(region_id) do
      {:ok, region} -> replicas(region)
      {:error, _reason} -> 1
    end
  end

  @doc """
  The region's egress as the scheduler sees it: what each Ready box advertises
  and has reserved, and where each account's pods sit.

  One read for the whole region rather than one per account, because the ops
  page asks this for every region an account holds an instance in.
  """
  def egress_placement(region_id) do
    KeyValueStore.get_or_update(
      [__MODULE__, "egress_placement", region_id],
      [ttl: to_timeout(minute: 1), locking: true],
      fn -> measure_egress_placement(region_id) end
    )
  end

  defp measure_egress_placement(region_id) do
    with {:ok, region} <- Regions.fetch(region_id),
         selector when is_binary(selector) <- Regions.node_label_selector(region),
         {:ok, %{"items" => node_items}} <- Client.list_nodes(selector) do
      node_items
      |> Enum.filter(&ready?/1)
      |> Enum.reduce_while(%{nodes: %{}, accounts: %{}}, fn node, acc ->
        case {node_name(node), egress_mbps(node)} do
          {name, mbps} when is_binary(name) and is_integer(mbps) ->
            measure_node_egress(acc, name, mbps, region_id)

          _ ->
            {:cont, acc}
        end
      end)
      |> case do
        nil -> nil
        %{accounts: accounts} = placement -> %{placement | accounts: close_account_placement(accounts)}
      end
    else
      _ -> nil
    end
  end

  # One list per box, cluster-wide, rather than one list of the pods this control
  # plane labels: what bounds a tenant's floor is everything reserved on its box,
  # whoever put it there, and a narrower list overstates the room left by
  # whatever it does not see.
  #
  # A box that cannot be read abandons the whole measurement rather than
  # answering from the ones that could — a region reading as roomier than it is
  # would be worse than reading as unknown, which falls back to the advertised
  # budget.
  defp measure_node_egress(acc, node, allocatable_mbps, region_id) do
    case Client.list_pods_on_node(node) do
      {:ok, pods} ->
        # The field selector already narrows this to the box, and a pod holds a
        # node's resources from the moment it is bound rather than when it
        # starts. Re-checking the binding here keeps that invariant next to the
        # arithmetic that depends on it, instead of in a query string.
        pods = Enum.filter(pods, &(pod_node_name(&1) == node and not terminal?(&1)))

        nodes =
          Map.put(acc.nodes, node, %{
            allocatable_mbps: allocatable_mbps,
            reserved_mbps: pods |> Enum.map(&pod_egress_mbps/1) |> Enum.sum()
          })

        {:cont, %{nodes: nodes, accounts: account_egress_placement(pods, acc.accounts, region_id)}}

      {:error, _reason} ->
        {:halt, nil}
    end
  end

  # Which account each pod belongs to, and what it holds where, accumulated
  # across the region's boxes. Only pods that carry the controller's account
  # label are anybody's — everything else on a box is simply reserved against it.
  #
  # Scoped to this region as well as to the account, which the node-wide list no
  # longer does on its own. A box can carry pods of the same account that belong
  # to something else — another region's instance, or a self-hosted deployment's
  # own — and counting those as replicas of the instance being sized divides the
  # box by too many. Observed on a lab node: three unrelated pods labelled with
  # the account turned a limit of 500 into one of 200.
  defp account_egress_placement(pods, accounts, region_id) do
    Enum.reduce(pods, accounts, fn pod, acc ->
      with handle when is_binary(handle) <- pod_account_handle(pod),
           ^region_id <- pod_region(pod),
           node when is_binary(node) <- pod_node_name(pod) do
        entry = Map.get(acc, handle, %{nodes: %{}, replicas: 0})

        Map.put(acc, handle, %{
          nodes: Map.update(entry.nodes, node, pod_egress_mbps(pod), &(&1 + pod_egress_mbps(pod))),
          replicas: entry.replicas + 1
        })
      else
        _ -> acc
      end
    end)
  end

  defp close_account_placement(accounts) do
    Map.new(accounts, fn {handle, entry} -> {handle, %{entry | nodes: Map.to_list(entry.nodes)}} end)
  end

  defp node_name(%{"metadata" => %{"name" => name}}), do: name
  defp node_name(_node), do: nil

  defp pod_node_name(%{"spec" => %{"nodeName" => name}}) when is_binary(name) and name != "", do: name
  defp pod_node_name(_pod), do: nil

  defp pod_account_handle(%{"metadata" => %{"labels" => %{"tuist.dev/account" => handle}}}), do: handle
  defp pod_account_handle(_pod), do: nil

  defp pod_region(%{"metadata" => %{"labels" => %{"tuist.dev/region" => region_id}}}), do: region_id
  defp pod_region(_pod), do: nil

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
