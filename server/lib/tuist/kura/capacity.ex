defmodule Tuist.Kura.Capacity do
  @moduledoc """
  Whether a region has room for one more warm Kura instance.

  A region's capacity is its installed machines times the usable filesystem
  each one contributes. What an instance consumes against that is its enforced
  warm quota — the quota-enforced directory it holds whether or not it is
  serving traffic — so the region's forecast is the sum of the quotas of every
  instance that is not archived.

  Two callers, one model:

    * provisioning admission. A cold provision is admitted only when the
      region's forecast still fits after adding the candidate's quota.
      Refusing leaves the account building without a cache, which is slow
      rather than broken, and raises a capacity event. Nothing here ever
      overcommits a node.

    * the Air pressure rule. Air's inactivity window shortens from 90 to 60
      complete days only while a region's forecast exceeds what is installed.
      When there is room the 90-day target is preserved.

  Installed capacity is summed from the region's own Ready nodes rather than
  declared: the regions do not run the same hardware, so a single assumed size
  per machine is wrong by whatever the real boxes differ by, and wrong in the
  direction that overcommits. Reading each node also means a machine that is
  down stops counting, which a declared figure could never express.

  What an instance holds is its per-replica quota times its replica count. The
  bare-metal regions co-locate an account's replicas on one box, so two
  replicas are two copies of the quota on the same disk.

  A region whose capacity cannot be established is unknown:
  provisioning is admitted (refusing every account because the apiserver was
  briefly unreachable would be worse than the overcommit it guards against,
  and the per-tick provisioning ceiling still bounds the blast radius) and
  pressure archival never runs, so the 90-day target holds. That covers the
  local controller, which has no node pool, and any transient API failure.
  """

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Billing
  alias Tuist.KeyValueStore
  alias Tuist.Kubernetes.Client
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server
  alias Tuist.Repo

  @gib 1024 * 1024 * 1024

  # Share of a node's allocatable filesystem that is actually usable before
  # kubelet starts evicting. The tighter of kubelet's two thresholds on this
  # fleet is `imagefs.available<15%`, and imagefs shares the disk the cache
  # ring lives on, so an instance filling past this line takes the node's
  # whole region down with it rather than just itself. Applied to allocatable
  # rather than capacity, which double-counts kubelet's own reserve slightly
  # and errs toward refusing a provision rather than overcommitting a box.
  @usable_fraction 0.85

  # Replicas an instance runs when its region declares none, matching the
  # kura-controller's own default. Guessing lower here would understate what
  # a region holds, which is the direction that overcommits.
  @default_replicas 3

  # The enforced warm quota per plan. Air's is the spec's figure. Paid plans
  # take the per-instance storage claim the region catalog already provisions
  # (`storage_size`), so this stays one number per instance rather than a
  # second, drifting sizing table.
  @air_quota_gib 24
  @default_quota_gib 50

  @doc """
  Bytes of the region's disk an instance of this plan holds, across every
  replica it runs.
  """
  def resident_bytes(plan, region), do: resident_gib(plan, region) * @gib

  @doc """
  Gibibytes of the region's disk an instance of this plan holds.

  An instance is a StatefulSet, and each replica keeps a full copy of the
  cache on the node it runs on -- the bare-metal regions deliberately
  co-locate an account's replicas on one box, so two replicas are two copies
  of the quota on the same disk, not one copy spread across two. Counting a
  single quota per instance is what let two replicas each size themselves
  against a whole node in July.
  """
  def resident_gib(plan, region), do: warm_quota_gib(plan, region) * replicas(region)

  @doc "Gibibytes one replica of this plan budgets for its cache ring."
  def warm_quota_gib(:air, _region), do: @air_quota_gib

  def warm_quota_gib(_plan, %Regions{provisioner_config: %{storage_size: size}}) when is_binary(size) do
    parse_gib(size) || @default_quota_gib
  end

  def warm_quota_gib(_plan, _region), do: @default_quota_gib

  defp replicas(%Regions{provisioner_config: %{replicas: replicas}}) when is_integer(replicas) and replicas > 0,
    do: replicas

  defp replicas(%Regions{}), do: @default_replicas

  @doc """
  Installed usable capacity of a region in gibibytes, or `nil` when it cannot
  be established.
  """
  def installed_gib(region_id) do
    KeyValueStore.get_or_update(
      [__MODULE__, "installed_gib", region_id],
      [ttl: to_timeout(minute: 1), locking: true],
      fn -> measure_installed_gib(region_id) end
    )
  end

  # Summed from the nodes themselves rather than from a machine count times an
  # assumed size per machine: the regions do not run the same hardware, and an
  # assumed figure is wrong in whichever direction the real boxes differ.
  defp measure_installed_gib(region_id) do
    with {:ok, region} <- Regions.fetch(region_id),
         selector when is_binary(selector) <- Regions.node_label_selector(region),
         {:ok, %{"items" => items}} <- Client.list_nodes(selector) do
      items
      |> Enum.filter(&ready?/1)
      |> Enum.map(&allocatable_bytes/1)
      |> Enum.sum()
      |> usable_gib()
    else
      _ -> nil
    end
  end

  defp usable_gib(0), do: nil
  defp usable_gib(bytes), do: trunc(bytes * @usable_fraction / @gib)

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
  Gibibytes of the region's disk its non-archived instances already hold.
  Destroyed and archived rows hold nothing: their directories are gone.
  """
  def forecast_gib(region_id) do
    case Regions.fetch(region_id) do
      {:ok, region} ->
        region_id
        |> warm_instance_plans()
        |> Enum.reduce(0, fn plan, total -> total + resident_gib(plan, region) end)

      {:error, _reason} ->
        0
    end
  end

  @doc """
  Whether one more instance of `plan` fits in the region.

  Returns `:ok`, or `{:error, :no_safe_slot}` with the forecast that refused
  it so the caller can raise a capacity event carrying real numbers.
  """
  def admit(region_id, plan) do
    with {:ok, region} <- Regions.fetch(region_id) do
      case installed_gib(region_id) do
        nil ->
          :ok

        installed ->
          forecast = forecast_gib(region_id) + resident_gib(plan, region)

          if forecast <= installed do
            :ok
          else
            {:error, {:no_safe_slot, %{region: region_id, forecast_gib: forecast, installed_gib: installed}}}
          end
      end
    end
  end

  @doc """
  Whether the region's forecast enforced warm quota no longer fits what is
  installed. Only under that pressure may Air instances be drained at 60
  complete inactive days instead of 90.
  """
  def under_pressure?(region_id) do
    case installed_gib(region_id) do
      nil -> false
      installed -> forecast_gib(region_id) > installed
    end
  end

  @doc """
  Region occupancy as `%{forecast_gib:, installed_gib:, instances:, ratio:}`,
  for the region occupancy metric. `installed_gib` and `ratio` are `nil` when
  the region's installed capacity cannot be established.
  """
  def occupancy(region_id) do
    forecast = forecast_gib(region_id)
    installed = installed_gib(region_id)

    %{
      forecast_gib: forecast,
      installed_gib: installed,
      instances: length(warm_instance_plans(region_id)),
      ratio: if(installed && installed > 0, do: forecast / installed)
    }
  end

  # The effective plan of every instance holding a directory in the region. A
  # move leaves two rows for one account; both hold a directory, so both
  # count. Two queries rather than a correlated subquery so plan resolution
  # stays `Billing.effective_plan/1` and cannot drift from it.
  defp warm_instance_plans(region_id) do
    account_ids =
      Repo.all(
        from(s in Server,
          where: s.region == ^region_id,
          where: s.status not in [:destroyed, :archived],
          select: s.account_id
        )
      )

    if account_ids == [] do
      []
    else
      plans =
        Account
        |> where([a], a.id in ^account_ids)
        |> preload(:subscriptions)
        |> Repo.all()
        |> Map.new(&{&1.id, Billing.effective_plan(&1)})

      Enum.map(account_ids, &Map.get(plans, &1, :air))
    end
  end

  defp parse_gib(size) do
    case Integer.parse(size) do
      {value, "Gi"} -> value
      {value, "G"} -> value
      _ -> nil
    end
  end
end
