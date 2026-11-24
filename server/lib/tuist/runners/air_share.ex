defmodule Tuist.Runners.AirShare do
  @moduledoc """
  The share of each platform's runner fleet that Air accounts may hold
  together.

  Each Air account has its own small concurrency limit, but nothing bounds
  how many Air accounts run at once, so a burst of sign-ups could fill the
  fleet paid accounts rely on. Admission (`Tuist.Runners.Claims.attempt/6`)
  therefore also refuses an Air account's claim once Air claims on the
  platform would exceed `share_percent/0` of the fleet's capacity, and the
  scaling signals stop counting Air jobs past that share as demand.

  An account counts as Air when it has no live paid or open source
  subscription and is not on a runner trial, the same accounts
  `Tuist.Runners.Allowance` cuts off at the free allowance.

  Capacity is the allocatable CPU and memory of the Ready, schedulable
  Nodes behind the platform's RunnerPools, read from the cluster and cached
  for a minute. While it cannot be read (outside a cluster, or an API
  outage) the share is not enforced: Air accounts are still bounded by
  their own limits, and refusing every Air job on a read failure would be
  an outage of its own.
  """

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Billing
  alias Tuist.Billing.Subscription
  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.Kubernetes.Client
  alias Tuist.Kubernetes.Quantity
  alias Tuist.Repo
  alias Tuist.Runners.Claim
  alias Tuist.Runners.Concurrency
  alias Tuist.Runners.Trials

  require Logger

  @platforms [:linux, :macos]
  # Paid and open source plans in `subscriptions.plan`.
  @unshared_plans [:enterprise, :pro, :open_source]
  @capacity_ttl to_timeout(minute: 1)
  @read_timeout to_timeout(second: 5)
  # First key of the two-key advisory lock that serialises Air admission
  # per platform, so concurrent claims of different Air accounts cannot
  # each fit the share on their own and overshoot it together.
  @lock_namespace 917_201
  @platform_lock_keys %{linux: 1, macos: 2}

  @doc "The percentage of each platform's capacity Air accounts may hold together."
  def share_percent, do: Application.get_env(:tuist, :runner_air_fleet_share_percent, 15)

  @doc "True when `account` is subject to the Air share."
  def air_account?(%Account{} = account) do
    not Trials.on_trial?(account) and Billing.effective_plan(account) not in @unshared_plans
  end

  @doc """
  The resources Air accounts may hold together on `platform`, or
  `:unknown` while the fleet's capacity cannot be read.
  """
  def budget(platform) when platform in @platforms do
    case capacity(platform) do
      {:ok, %{vcpus: vcpus, memory_gb: memory_gb}} ->
        percent = share_percent()
        %{vcpus: div(vcpus * percent, 100), memory_gb: div(memory_gb * percent, 100)}

      :unknown ->
        :unknown
    end
  end

  @doc """
  Admits a claim of `resources` for `account` against the Air share, inside
  the claim's transaction. `budget` is `budget/1` read before the
  transaction, so no cluster read happens while it holds locks.

  Returns `:ok`, `{:error, :account_busy}` when another Air admission on
  the platform holds the lock, or `{:error, {:air_fleet_share_reached,
  details}}`. The claim being admitted is already inserted, so its own
  resources are subtracted from the usage read back.
  """
  def check(_account, _resources, :unknown), do: :ok

  def check(%Account{} = account, %{platform: platform} = resources, budget) do
    cond do
      not air_account?(account) ->
        :ok

      not try_lock(platform) ->
        {:error, :account_busy}

      true ->
        usage = usage(platform)
        used = %{vcpus: usage.vcpus - resources.vcpus, memory_gb: usage.memory_gb - resources.memory_gb}

        if Concurrency.fits?(used, budget, resources) do
          :ok
        else
          {:error, {:air_fleet_share_reached, %{platform: platform, requested: resources, used: used, budget: budget}}}
        end
    end
  end

  @doc """
  How many more jobs of shape `resources` Air accounts may start together,
  or `:unlimited` while the fleet's capacity cannot be read. The scaling
  signals cap Air accounts' queued jobs at it.
  """
  def remaining_jobs(%{platform: platform, vcpus: vcpus, memory_gb: memory_gb})
      when platform in @platforms and vcpus > 0 and memory_gb > 0 do
    case budget(platform) do
      :unknown ->
        :unlimited

      budget ->
        used = usage(platform)

        max(0, min(div(budget.vcpus - used.vcpus, vcpus), div(budget.memory_gb - used.memory_gb, memory_gb)))
    end
  end

  def remaining_jobs(_resources), do: :unlimited

  @doc "The subset of `account_ids` that are Air accounts."
  def air_account_ids([]), do: MapSet.new()

  def air_account_ids(account_ids) when is_list(account_ids) do
    from(a in Account, where: a.id in ^account_ids, select: a.id)
    |> air_accounts()
    |> Repo.all()
    |> MapSet.new()
  end

  defp usage(platform) do
    air_ids = air_accounts(from(a in Account, select: a.id))

    Repo.one(
      from(c in Claim,
        where: c.platform == ^platform and c.account_id in subquery(air_ids),
        select: %{vcpus: coalesce(sum(c.vcpus), 0), memory_gb: coalesce(sum(c.memory_gb), 0)}
      )
    )
  end

  defp air_accounts(query) do
    live = Billing.live_subscription_statuses()

    from(a in query,
      as: :account,
      where: not (not is_nil(a.runner_trial_started_at) and is_nil(a.runner_trial_ended_at)),
      where:
        not exists(
          from(s in Subscription,
            where: s.account_id == parent_as(:account).id and s.status in ^live and s.plan in ^@unshared_plans
          )
        )
    )
  end

  defp try_lock(platform) do
    %{rows: [[locked?]]} =
      Repo.query!("SELECT pg_try_advisory_xact_lock($1, $2)", [
        @lock_namespace,
        Map.fetch!(@platform_lock_keys, platform)
      ])

    locked?
  end

  @doc """
  Allocatable `%{vcpus, memory_gb}` of the Ready, schedulable Nodes behind
  `platform`'s RunnerPools, or `:unknown`. Cached for a minute, failures
  included, so an unreadable cluster costs one read a minute.
  """
  def capacity(platform) when platform in @platforms do
    [__MODULE__, :capacity]
    |> KeyValueStore.get_or_update([ttl: @capacity_ttl], &read_capacity/0)
    |> case do
      {:ok, by_platform} -> by_platform |> Map.get(platform) |> known_capacity()
      _ -> :unknown
    end
  end

  defp known_capacity(%{vcpus: vcpus, memory_gb: memory_gb} = capacity) when vcpus > 0 and memory_gb > 0,
    do: {:ok, capacity}

  defp known_capacity(_), do: :unknown

  defp read_capacity do
    with_result =
      with {:ok, pools} <- Client.list_runner_pools(Environment.runners_namespace()) do
        pools
        |> Enum.flat_map(&pool_fleet/1)
        |> Enum.uniq()
        |> Enum.reduce_while({:ok, %{}}, fn {platform, selector}, {:ok, acc} ->
          case Client.list_nodes(selector, timeout: @read_timeout) do
            {:ok, %{"items" => nodes}} when is_list(nodes) ->
              {:cont, {:ok, Map.update(acc, platform, nodes_capacity(nodes), &add(&1, nodes_capacity(nodes)))}}

            other ->
              {:halt, {:error, other}}
          end
        end)
      end

    case with_result do
      {:ok, _} = ok ->
        ok

      error ->
        Logger.warning("runners: could not read fleet capacity; not enforcing the Air share", reason: inspect(error))
        :unknown
    end
  end

  defp pool_fleet(%{"spec" => %{"fleetSelector" => fleet} = spec}) when is_binary(fleet) and fleet != "" do
    case Map.get(spec, "os", "darwin") do
      "linux" -> [{:linux, "node.cluster.x-k8s.io/pool=#{fleet},kubernetes.io/os=linux"}]
      _ -> [{:macos, "tuist.dev/fleet=#{fleet},kubernetes.io/os=darwin"}]
    end
  end

  defp pool_fleet(_pool), do: []

  defp nodes_capacity(nodes) do
    nodes
    |> Enum.filter(&schedulable?/1)
    |> Enum.reduce(%{vcpus: 0, memory_gb: 0}, fn node, acc ->
      add(acc, %{
        vcpus: div(allocatable(node, "cpu", 1000), 1000),
        memory_gb: div(allocatable(node, "memory", 1), 1024 * 1024 * 1024)
      })
    end)
  end

  defp add(a, b), do: %{vcpus: a.vcpus + b.vcpus, memory_gb: a.memory_gb + b.memory_gb}

  defp schedulable?(node) do
    get_in(node, ["spec", "unschedulable"]) != true and
      Enum.any?(get_in(node, ["status", "conditions"]) || [], &match?(%{"type" => "Ready", "status" => "True"}, &1))
  end

  defp allocatable(node, resource, scale) do
    node |> get_in(["status", "allocatable", resource]) |> Quantity.parse(scale) || 0
  end
end
