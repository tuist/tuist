defmodule Tuist.Runners.Concurrency do
  @moduledoc """
  Platform-specific vCPU and memory concurrency limits for Tuist
  Runners.

  Linux and macOS have independent budgets. A claim is admitted only
  when adding its shape keeps both aggregate vCPU and aggregate memory
  within the account's limits for that platform. `Claims.attempt/5`
  owns the database-backed read-check-insert transaction; this module
  provides the pure capacity predicate and reporting queries.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias Tuist.Accounts.Account
  alias Tuist.ClickHouseRepo
  alias Tuist.Repo
  alias Tuist.Runners.Claim
  alias Tuist.Runners.ConcurrencyLimit
  alias Tuist.Runners.RunnerSessions

  @platforms [:linux, :macos]
  @default_limits %{
    linux: %{vcpus: 32, memory_gb: 64},
    macos: %{vcpus: 12, memory_gb: 28}
  }
  @limit_form_fields [
    :runner_linux_vcpus_limit,
    :runner_linux_memory_gb_limit,
    :runner_macos_vcpus_limit,
    :runner_macos_memory_gb_limit
  ]
  @limit_form_types Map.new(@limit_form_fields, &{&1, :integer})

  @doc """
  Returns platform summaries with current claimed resources and limits.
  """
  def summaries(%Account{} = account) do
    usage = usage_by_platform(account.id)
    limits = limits_by_platform(account.id)

    Enum.map(@platforms, fn platform ->
      platform_usage = Map.fetch!(usage, platform)
      platform_limits = limits |> Map.fetch!(platform) |> limit_resources()

      %{
        platform: platform,
        used_vcpus: platform_usage.vcpus,
        used_memory_gb: platform_usage.memory_gb,
        limit_vcpus: platform_limits.vcpus,
        limit_memory_gb: platform_limits.memory_gb
      }
    end)
  end

  @doc """
  Returns aggregate active-claim resources for each platform.
  """
  def usage_by_platform(account_id) when is_integer(account_id) do
    usage =
      Claim
      |> where([claim], claim.account_id == ^account_id)
      |> group_by([claim], claim.platform)
      |> select([claim], {
        claim.platform,
        %{vcpus: sum(claim.vcpus), memory_gb: sum(claim.memory_gb)}
      })
      |> Repo.all()
      |> Map.new()

    Map.merge(zero_usage(), usage)
  end

  @doc """
  Returns the peak concurrent vCPU and memory usage per time bucket.

  Reconstructed from runner sessions, one per Pod the account held.
  Each becomes a positive resource event when its claim is taken and a
  negative one when the claim is released; running totals over that
  sweep are the concurrent usage, and bucketing happens afterwards so
  even a short-lived peak stays visible.

  The session is what holds the slot, which is why this reads it rather
  than the job. GitHub hands a queued job to any label-eligible runner,
  so the Pod that claimed job A frequently executes job B; charting
  `A.claimed_at → A.completed_at` measures a window the account was not
  reserving, and overstates the peak past a limit that admission makes
  it impossible to exceed.

  Served from `Tuist.Runners.ConcurrencySession`, the ClickHouse
  replica of those sessions, because the sweep is an analytical scan
  over every session in the window and the Postgres original is the
  primary that dispatch and claim transactions run on. The replica is
  fed by `Tuist.Runners.SessionReplication` and is a read-model: it
  never feeds a control-plane decision, so trailing the source by a
  tick costs nothing here.
  """
  def usage_over_time(account_id, %DateTime{} = start_dt, %DateTime{} = end_dt, bucket)
      when is_integer(account_id) and bucket in [:hour, :day] do
    dates = bucket_range(start_dt, end_dt, bucket)

    peaks = bucket_peaks(account_id, start_dt, end_dt, bucket)

    %{
      dates: dates,
      linux: peak_usage(Map.get(peaks, :linux, %{}), dates, bucket),
      macos: peak_usage(Map.get(peaks, :macos, %{}), dates, bucket)
    }
  end

  @doc """
  Purely checks whether `requested` fits within `limit` after `used`.
  """
  def fits?(
        %{vcpus: used_vcpus, memory_gb: used_memory_gb} = used,
        %{vcpus: limit_vcpus, memory_gb: limit_memory_gb} = limit,
        %{vcpus: requested_vcpus, memory_gb: requested_memory_gb} = requested
      ) do
    valid_usage?(used) and valid_capacity?(limit) and valid_capacity?(requested) and
      used_vcpus + requested_vcpus <= limit_vcpus and
      used_memory_gb + requested_memory_gb <= limit_memory_gb
  end

  def fits?(_used, _limit, _requested), do: false

  @doc """
  How many more jobs of shape `resources` the account could claim right
  now before hitting its platform concurrency limit.

  This is the *forward-looking* companion to `fits?/3`: `fits?/3` answers
  "does one more fit" at claim time, this answers "how many more fit" for
  callers that must size ahead of the claim. Both read the same usage and
  limit, so a job counted here is a job `fits?/3` would admit.

  The autoscaler is the caller that matters. Sizing a pool on raw queue
  depth provisions Pods for jobs dispatch will refuse, and those Pods
  then sit idle holding hosts that pools with claimable work cannot get.
  Capping each account's contribution at its headroom keeps the demand
  signal to what can actually be served.

  Returns 0 for an unknown account, a missing limit row, or a malformed
  shape: this runs on the autoscaler's poll path, where raising would
  fail the whole fleet's signal over one bad account.
  """
  def headroom_jobs(account_id, %{platform: platform, vcpus: vcpus, memory_gb: memory_gb})
      when is_integer(account_id) and platform in @platforms and is_integer(vcpus) and is_integer(memory_gb) and vcpus > 0 and
             memory_gb > 0 do
    case limit_for_platform(account_id, platform) do
      {:ok, limit} ->
        used = Map.get(usage_by_platform(account_id), platform, %{vcpus: 0, memory_gb: 0})

        [div(limit.vcpus - used.vcpus, vcpus), div(limit.memory_gb - used.memory_gb, memory_gb)]
        |> Enum.min()
        |> max(0)

      :error ->
        0
    end
  end

  def headroom_jobs(_account_id, _resources), do: 0

  defp limit_for_platform(account_id, platform) do
    case Repo.get_by(ConcurrencyLimit, account_id: account_id, platform: platform) do
      nil -> :error
      limit -> {:ok, limit_resources(limit)}
    end
  end

  defp valid_usage?(resources) do
    Enum.all?([resources.vcpus, resources.memory_gb], &(is_integer(&1) and &1 >= 0))
  end

  defp valid_capacity?(resources) do
    Enum.all?([resources.vcpus, resources.memory_gb], &(is_integer(&1) and &1 > 0))
  end

  @doc """
  Creates the default Linux and macOS limits for a new account.
  """
  def create_default_limits(%Account{id: account_id}) do
    Enum.reduce_while(@platforms, {:ok, []}, fn platform, {:ok, limits} ->
      attrs =
        @default_limits
        |> Map.fetch!(platform)
        |> Map.merge(%{account_id: account_id, platform: platform})

      case %ConcurrencyLimit{}
           |> ConcurrencyLimit.changeset(attrs)
           |> Repo.insert(on_conflict: :nothing, conflict_target: [:account_id, :platform]) do
        {:ok, limit} -> {:cont, {:ok, [limit | limits]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  @doc """
  Builds a changeset for the ops concurrency-limits form.
  """
  def change_limits(%Account{} = account, attrs \\ %{}) do
    limits = limits_by_platform(account.id)
    linux = limits |> Map.fetch!(:linux) |> limit_resources()
    macos = limits |> Map.fetch!(:macos) |> limit_resources()

    data = %{
      runner_linux_vcpus_limit: linux.vcpus,
      runner_linux_memory_gb_limit: linux.memory_gb,
      runner_macos_vcpus_limit: macos.vcpus,
      runner_macos_memory_gb_limit: macos.memory_gb
    }

    {data, @limit_form_types}
    |> Changeset.cast(attrs, @limit_form_fields)
    |> Changeset.validate_required(@limit_form_fields)
    |> Changeset.validate_number(:runner_linux_vcpus_limit, greater_than: 0)
    |> Changeset.validate_number(:runner_linux_memory_gb_limit, greater_than: 0)
    |> Changeset.validate_number(:runner_macos_vcpus_limit, greater_than: 0)
    |> Changeset.validate_number(:runner_macos_memory_gb_limit, greater_than: 0)
  end

  @doc """
  Persists custom concurrency limits for an account.
  """
  def update_limits(%Account{} = account, attrs) when is_map(attrs) do
    changeset = change_limits(account, attrs)

    case Changeset.apply_action(changeset, :update) do
      {:ok, values} ->
        Repo.transaction(fn ->
          limits =
            ConcurrencyLimit
            |> where([limit], limit.account_id == ^account.id)
            |> order_by([limit], limit.platform)
            |> lock("FOR UPDATE")
            |> Repo.all()

          if length(limits) != length(@platforms) do
            Repo.rollback(:runner_concurrency_limits_missing)
          end

          Enum.each(limits, fn limit ->
            attrs = form_values_for_platform(values, limit.platform)

            limit
            |> ConcurrencyLimit.changeset(attrs)
            |> Repo.update!()
          end)

          account
        end)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp form_values_for_platform(values, :linux) do
    %{
      vcpus: values.runner_linux_vcpus_limit,
      memory_gb: values.runner_linux_memory_gb_limit
    }
  end

  defp form_values_for_platform(values, :macos) do
    %{
      vcpus: values.runner_macos_vcpus_limit,
      memory_gb: values.runner_macos_memory_gb_limit
    }
  end

  # Per-bucket peak, computed in ClickHouse.
  #
  # The replica holds one interval per session, so the sweep is: expand
  # each into a claim and a release event, running-sum them into the
  # concurrent total, then reduce to one row per bucket. Only those
  # rows cross the wire — a few hundred, whatever the account's volume
  # — which is the point of the replica. The same sweep against
  # Postgres shipped an interval per session into the BEAM and cost
  # 122ms at 19k sessions, 798ms at 100k.
  #
  # `argMax(…, ingested_at) GROUP BY id` collapses re-ingests of the
  # same session. Without it two rows for one session would both count
  # and double its resources until a background merge happened to run.
  # Its outputs carry `latest_` names because an alias that shadows the
  # column it aggregates resolves back to the aggregate downstream, and
  # ClickHouse then rejects the filter as an aggregate in WHERE.
  #
  # `opens_bucket` carries the one thing the bucket totals cannot say
  # on their own: whether the earliest event lands exactly on the
  # boundary. If it does, the level it establishes replaces the one
  # carried in rather than competing with it.
  defp bucket_peaks(account_id, start_dt, end_dt, bucket) do
    scan_floor = DateTime.add(start_dt, -RunnerSessions.max_session_lifetime_seconds(), :second)

    query = """
    WITH latest AS (
      SELECT
        id,
        argMax(platform, ingested_at) AS latest_platform,
        argMax(vcpus, ingested_at) AS latest_vcpus,
        argMax(memory_gb, ingested_at) AS latest_memory_gb,
        argMax(started_at, ingested_at) AS latest_started_at,
        argMax(released_at, ingested_at) AS latest_released_at
      FROM runner_concurrency_sessions
      WHERE account_id = {account_id:Int64}
        AND started_at <= {end_dt:DateTime64(6)}
        AND started_at > {scan_floor:DateTime64(6)}
      GROUP BY id
    ),
    intervals AS (
      SELECT
        latest_platform AS platform,
        greatest(latest_started_at, {start_dt:DateTime64(6)}) AS active_from,
        least(latest_released_at, {end_dt:DateTime64(6)}) AS active_until,
        toInt64(latest_vcpus) AS vcpus,
        toInt64(latest_memory_gb) AS memory_gb
      FROM latest
      WHERE latest_released_at > {start_dt:DateTime64(6)}
    ),
    events AS (
      SELECT
        platform,
        tupleElement(event, 1) AS ts,
        sum(tupleElement(event, 2)) AS vcpus_delta,
        sum(tupleElement(event, 3)) AS memory_delta
      FROM intervals
      ARRAY JOIN [
        tuple(active_from, vcpus, memory_gb),
        tuple(active_until, -vcpus, -memory_gb)
      ] AS event
      GROUP BY platform, ts
    ),
    running AS (
      SELECT
        platform,
        ts,
        toInt64(sum(vcpus_delta) OVER running_total) AS vcpus,
        toInt64(sum(memory_delta) OVER running_total) AS memory_gb
      FROM events
      WINDOW running_total AS (
        PARTITION BY platform ORDER BY ts
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      )
    )
    SELECT
      platform,
      #{bucket_expression(bucket)} AS bucket,
      max(vcpus) AS max_vcpus,
      max(memory_gb) AS max_memory_gb,
      argMin(vcpus, ts) AS first_vcpus,
      argMin(memory_gb, ts) AS first_memory_gb,
      argMax(vcpus, ts) AS last_vcpus,
      argMax(memory_gb, ts) AS last_memory_gb,
      min(ts) = #{boundary_expression(bucket)}(min(ts)) AS opens_bucket
    FROM running
    GROUP BY platform, bucket
    ORDER BY platform, bucket
    """

    {:ok, %{rows: rows}} =
      ClickHouseRepo.query(query, %{
        account_id: account_id,
        start_dt: start_dt,
        end_dt: end_dt,
        scan_floor: scan_floor
      })

    rows
    |> Enum.map(&decode_bucket_peak(&1, bucket))
    |> Enum.group_by(& &1.platform, &{&1.key, &1})
    |> Map.new(fn {platform, buckets} -> {platform, Map.new(buckets)} end)
  end

  defp bucket_expression(:hour), do: "toStartOfHour(ts)"
  defp bucket_expression(:day), do: "toDate(ts)"

  defp boundary_expression(:hour), do: "toStartOfHour"
  defp boundary_expression(:day), do: "toStartOfDay"

  defp decode_bucket_peak(
         [
           platform,
           bucket,
           max_vcpus,
           max_memory_gb,
           first_vcpus,
           first_memory_gb,
           last_vcpus,
           last_memory_gb,
           opens_bucket
         ],
         bucket_unit
       ) do
    %{
      platform: String.to_existing_atom(platform),
      key: bucket_key(bucket, bucket_unit),
      peak: %{vcpus: max_vcpus, memory_gb: max_memory_gb},
      first: %{vcpus: first_vcpus, memory_gb: first_memory_gb},
      last: %{vcpus: last_vcpus, memory_gb: last_memory_gb},
      opens_bucket: opens_bucket == 1
    }
  end

  # Walks the bucket range carrying the concurrent level across buckets
  # the sweep produced no event in — the account still held those
  # resources, there was simply nothing to record.
  defp peak_usage(peaks, dates, bucket) do
    {values, _carried} =
      Enum.map_reduce(dates, %{vcpus: 0, memory_gb: 0}, fn date, carried ->
        case Map.get(peaks, bucket_key(date, bucket)) do
          nil ->
            {carried, carried}

          bucket_peak ->
            starting = if bucket_peak.opens_bucket, do: bucket_peak.first, else: carried

            peak = %{
              vcpus: max(starting.vcpus, bucket_peak.peak.vcpus),
              memory_gb: max(starting.memory_gb, bucket_peak.peak.memory_gb)
            }

            {peak, bucket_peak.last}
        end
      end)

    %{
      vcpus: Enum.map(values, & &1.vcpus),
      memory_gb: Enum.map(values, & &1.memory_gb)
    }
  end

  # ClickHouse and `bucket_range/3` describe the same bucket with
  # different structs, so both go through one canonical key.
  defp bucket_key(%Date{} = date, :day), do: Date.to_erl(date)
  defp bucket_key(%DateTime{} = datetime, :day), do: datetime |> DateTime.to_date() |> Date.to_erl()
  defp bucket_key(%NaiveDateTime{} = datetime, :day), do: datetime |> NaiveDateTime.to_date() |> Date.to_erl()

  defp bucket_key(%DateTime{} = datetime, :hour), do: datetime |> floor_to_hour() |> DateTime.to_unix()

  defp bucket_key(%NaiveDateTime{} = datetime, :hour) do
    datetime |> DateTime.from_naive!("Etc/UTC") |> bucket_key(:hour)
  end

  defp bucket_range(%DateTime{} = start_dt, %DateTime{} = end_dt, :day) do
    start_dt |> DateTime.to_date() |> Date.range(DateTime.to_date(end_dt)) |> Enum.to_list()
  end

  defp bucket_range(%DateTime{} = start_dt, %DateTime{} = end_dt, :hour) do
    floor_start = floor_to_hour(start_dt)
    floor_end = floor_to_hour(end_dt)

    floor_start
    |> Stream.iterate(&DateTime.add(&1, 1, :hour))
    |> Enum.take_while(&(DateTime.compare(&1, floor_end) != :gt))
  end

  defp floor_to_hour(%DateTime{} = datetime) do
    %{datetime | minute: 0, second: 0, microsecond: {0, 0}}
  end

  @doc """
  Returns the configured resource limits for `platform`.
  """
  def limits_for(%Account{id: account_id}, platform), do: limits_for(account_id, platform)

  def limits_for(account_id, platform) when is_integer(account_id) and platform in @platforms do
    ConcurrencyLimit
    |> Repo.get_by!(account_id: account_id, platform: platform)
    |> limit_resources()
  end

  def limit_resources(%ConcurrencyLimit{} = limit) do
    %{vcpus: limit.vcpus, memory_gb: limit.memory_gb}
  end

  defp limits_by_platform(account_id) do
    ConcurrencyLimit
    |> where([limit], limit.account_id == ^account_id)
    |> Repo.all()
    |> Map.new(&{&1.platform, &1})
  end

  defp zero_usage do
    %{
      linux: %{vcpus: 0, memory_gb: 0},
      macos: %{vcpus: 0, memory_gb: 0}
    }
  end
end
