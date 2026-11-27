defmodule Tuist.RemoteExecution.LearnedFloor do
  @moduledoc """
  A remote execution floor learned from the accounts' own builds, for the
  runners-controller's compute allocator (`remote_execution_floor_slots` in
  `Tuist.Runners.scaling_signals_for_fleet/1`), the way
  `Tuist.Runners.LearnedWarmFloors` learns runner pools' warm floors.

  A build sends most of its first wave of actions within a couple of seconds
  of its first one. Workers already hold the memory for some of them (the
  chart's fixed floor); the rest wait for their carve-outs to grow, which on
  shared hosts waits for the kubelet and for idle runners to be retired. With
  the fixed floor at 10 slots, a build's first actions waited about 24 s at
  the median (production, 2026-11-26), against about 2 s while 86 GiB stayed
  warm. So the floor is the first wave: per account, the 90th percentile,
  over its builds of the last 14 days, of the memory the actions queued in a
  build's first 2 s asked for, in slots.

  Builds come in batches: three quarters of them start within 30 minutes of
  the previous one. The floor applies only while the account has started a
  build in the last 30 minutes, so it is held through a batch (about a tenth
  of the week in November 2026) and given back to CI otherwise. The first
  build of a batch still starts on the fixed floor.

  Each account's floor is capped at what its account limit lets it run at
  once, and the floors of the active accounts are summed. The controller caps
  the sum (`--remote-execution-max-learned-floor-slots`) and never goes below
  its fixed floor.

  One query computes every account. Each replica caches the result for 30
  seconds, so a batch's first build raises the floor quickly while the
  autoscaler's polls never reach ClickHouse.
  """

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.ClickHouseRepo
  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.Repo

  require Logger

  @history_days 14
  @burst_ms 2_000
  @burst_quantile 0.9
  @active_within_minutes 30
  # One worker slot: a 4 GiB guest plus the 64 MiB VMM overhead
  # (`Tuist.Sandboxes.Capacity.charge_bytes/1`), the slot the
  # runners-controller and the remote-execution chart count in.
  @slot_mib 4_160
  @vm_overhead_mib 64
  @cache_ttl to_timeout(second: 30)

  @doc """
  The learned floor in worker slots: the sum over accounts with a build
  started in the last 30 minutes. 0 when none is active.
  """
  def slots, do: by_account() |> Map.values() |> Enum.sum()

  @doc """
  Each active account's floor in worker slots, capped at its account limit,
  keyed by account ID.
  """
  def by_account do
    if Environment.test?() do
      compute()
    else
      KeyValueStore.get_or_update([:remote_execution, :learned_floor, :v1], [ttl: @cache_ttl], &compute/0)
    end
  end

  defp compute do
    case active_floors() do
      [] -> %{}
      floors -> cap_by_account_limits(floors)
    end
  end

  defp active_floors do
    query = """
    WITH actions AS (
      SELECT
        account_id,
        invocation_id,
        memory_gb,
        assumeNotNull(queued_at) AS queued,
        min(assumeNotNull(queued_at)) OVER (PARTITION BY invocation_id) AS first_queued
      FROM remote_execution_actions
      WHERE inserted_at >= now() - toIntervalDay({history_days:UInt32})
        AND invocation_id != ''
        AND queued_at IS NOT NULL
        AND NOT cached_result
    ),
    builds AS (
      SELECT
        any(account_id) AS account,
        min(first_queued) AS started,
        toInt32(ceil(
          sumIf(memory_gb * 1024 + {vm_overhead_mib:UInt32}, dateDiff('millisecond', first_queued, queued) <= {burst_ms:UInt32})
          / {slot_mib:UInt32}
        )) AS slots
      FROM actions
      GROUP BY invocation_id
    )
    SELECT account, toInt32(quantileExact({burst_quantile:Float64})(slots))
    FROM builds
    GROUP BY account
    HAVING max(started) >= now() - toIntervalMinute({active_within_minutes:UInt32})
    """

    params = %{
      history_days: @history_days,
      burst_ms: @burst_ms,
      burst_quantile: @burst_quantile,
      active_within_minutes: @active_within_minutes,
      slot_mib: @slot_mib,
      vm_overhead_mib: @vm_overhead_mib
    }

    case ClickHouseRepo.query(query, params) do
      {:ok, %{rows: rows}} ->
        for [account_id, floor] <- rows, floor > 0, do: {account_id, floor}

      {:error, reason} ->
        Logger.warning("remote execution: failed to compute the learned floor", reason: inspect(reason))
        []
    end
  end

  # A warm slot the account cannot fill only holds memory CI needs.
  defp cap_by_account_limits(floors) do
    limits =
      from(a in Account,
        where: a.id in ^Enum.map(floors, &elem(&1, 0)),
        select: {a.id, a.remote_execution_memory_gb_limit}
      )
      |> Repo.all()
      |> Map.new()

    for {account_id, floor} <- floors, memory_gb = limits[account_id], is_integer(memory_gb), into: %{} do
      {account_id, min(floor, div(memory_gb * 1024, @slot_mib - @vm_overhead_mib))}
    end
  end
end
