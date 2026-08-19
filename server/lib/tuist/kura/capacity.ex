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

  Installed machines are counted from the cluster: the Ready nodes carrying
  the region's node-pool label. A hand-maintained count would be a copy of
  something the cluster already knows, and it would drift in the direction
  that hurts — scale a pool down and the stale number keeps admitting against
  machines that are gone. Counting only Ready nodes also means a machine that
  is down stops counting as installed capacity, which a config value cannot
  express.

  A region whose count cannot be established has unknown capacity:
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

  # Usable filesystem a single machine contributes, after the reserves the
  # host itself needs. From the regional capacity model in the spec.
  @usable_gib_per_machine 1105

  # The enforced warm quota per plan. Air's is the spec's figure. Paid plans
  # take the per-instance storage claim the region catalog already provisions
  # (`storage_size`), so this stays one number per instance rather than a
  # second, drifting sizing table.
  @air_quota_gib 24
  @default_quota_gib 50

  @doc "Bytes of quota-enforced directory an instance of this plan holds."
  def warm_quota_bytes(plan, region), do: warm_quota_gib(plan, region) * @gib

  @doc "Gibibytes of quota-enforced directory an instance of this plan holds."
  def warm_quota_gib(:air, _region), do: @air_quota_gib

  def warm_quota_gib(_plan, %Regions{provisioner_config: %{storage_size: size}}) when is_binary(size) do
    parse_gib(size) || @default_quota_gib
  end

  def warm_quota_gib(_plan, _region), do: @default_quota_gib

  @doc """
  Installed usable capacity of a region in gibibytes, or `nil` when the
  region's machine count cannot be established.
  """
  def installed_gib(region_id) do
    case machines(region_id) do
      machines when is_integer(machines) and machines > 0 -> machines * @usable_gib_per_machine
      _ -> nil
    end
  end

  # Cached for a tick's worth of provisioning: `admit/2` is called once per
  # candidate account, and a pool's size does not change between two accounts
  # in the same pass.
  defp machines(region_id) do
    KeyValueStore.get_or_update(
      [__MODULE__, "machines", region_id],
      [ttl: to_timeout(minute: 1), locking: true],
      fn -> count_ready_nodes(region_id) end
    )
  end

  defp count_ready_nodes(region_id) do
    with {:ok, region} <- Regions.fetch(region_id),
         selector when is_binary(selector) <- Regions.node_label_selector(region),
         {:ok, %{"items" => items}} <- Client.list_nodes(selector) do
      Enum.count(items, &ready?/1)
    else
      _ -> nil
    end
  end

  defp ready?(%{"status" => %{"conditions" => conditions}}) when is_list(conditions) do
    Enum.any?(conditions, &match?(%{"type" => "Ready", "status" => "True"}, &1))
  end

  defp ready?(_node), do: false

  @doc """
  Gibibytes of enforced warm quota the region's non-archived instances already
  hold. Destroyed and archived rows hold nothing: their directories are gone.
  """
  def forecast_gib(region_id) do
    case Regions.fetch(region_id) do
      {:ok, region} ->
        region_id
        |> warm_instance_plans()
        |> Enum.reduce(0, fn plan, total -> total + warm_quota_gib(plan, region) end)

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
          forecast = forecast_gib(region_id) + warm_quota_gib(plan, region)

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
  for the per-machine occupancy metric. `installed_gib` and `ratio` are `nil`
  when the machine count is not configured.
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
