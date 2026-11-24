defmodule Tuist.Sandboxes.Analytics do
  @moduledoc """
  Account-scoped sandbox analytics over the `sandbox_events` ClickHouse
  table, for the dashboard's charts.

  Counts come straight from `created` events. Run sessions pair each
  `started` event with the sandbox's next stop event; a session with no stop
  yet runs until now. Compute, session durations and peak vCPUs and memory
  are derived from those sessions.

  The vCPU-hours an account is billed for (`compute/2`) come from two
  sources. A sandbox that bursts (its `started` event's guaranteed CPU is
  below its vCPUs) is metered at every node report, the larger of its
  CPU floor and the CPU it used, in `sandbox_usage_events`. Any other
  session counts its vCPUs for as long as it runs, up to its sandbox's first
  metered report, which is where a session that began before metering hands
  over. Memory (GiB-hours) is max(request, use): every running session's
  memory for as long as it runs, bursting or not, plus what a metered VM
  held past its request (`excess_memory_mib_ms` in `sandbox_usage_events`).

  Setup and time to start come straight from the durations events carry: a
  `setup` event's is how long an Orb's `.agents/setup` ran, and a
  `started` event that booted the sandbox (create or restore) carries how
  long the boot took.
  """

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Sandboxes.Events
  alias Tuist.Sandboxes.SandboxEvent
  alias Tuist.Sandboxes.UsageEvent

  @hourly_bucket_max_hours 36
  @session_lookback_days 7

  def bucket_for_window(%DateTime{} = start_dt, %DateTime{} = end_dt) do
    if DateTime.diff(end_dt, start_dt, :hour) <= @hourly_bucket_max_hours, do: :hour, else: :day
  end

  @doc """
  Returns every series the sandboxes overview charts for the window between
  `start_datetime` and `end_datetime`, each with its trend against the
  window of the same length before it.
  """
  def overview(account_id, opts) when is_integer(account_id) do
    end_dt = Keyword.get(opts, :end_datetime, DateTime.utc_now())
    start_dt = Keyword.get(opts, :start_datetime, DateTime.add(end_dt, -30, :day))
    prev_start_dt = DateTime.add(start_dt, -DateTime.diff(end_dt, start_dt, :second), :second)
    bucket = Keyword.get(opts, :bucket) || bucket_for_window(start_dt, end_dt)
    buckets = buckets(start_dt, end_dt, bucket)
    dates = Enum.map(buckets, & &1.date)

    # The date picker ends a window at the current second, truncated, so the
    # queries include events up to the end of that second.
    query_end_dt = DateTime.add(end_dt, 1, :second)

    by_sandbox = account_id |> lifecycle_events(prev_start_dt, query_end_dt) |> Enum.chunk_by(& &1.sandbox_id)
    sessions = sessions(by_sandbox, query_end_dt)
    events = List.flatten(by_sandbox)
    durations = &event_durations(events, &1, buckets, prev_start_dt, start_dt, query_end_dt)

    %{
      dates: dates,
      created: event_count(account_id, "created", buckets, prev_start_dt, start_dt, query_end_dt),
      session_duration: session_duration(sessions, buckets, prev_start_dt, start_dt, end_dt),
      setup: durations.(&(&1.event == "setup")),
      time_to_start: durations.(&(&1.event == "started" and &1.boot_source != "")),
      concurrency: concurrency(clip(sessions, start_dt, end_dt), buckets)
    }
  end

  @doc """
  The vCPU-hours and memory GiB-hours the account's sandboxes were billed
  for between `start_datetime` and `end_datetime`, in total and per day.
  """
  def compute(account_id, opts) when is_integer(account_id) do
    end_dt = Keyword.fetch!(opts, :end_datetime)
    start_dt = Keyword.fetch!(opts, :start_datetime)
    query_end_dt = DateTime.add(end_dt, 1, :second)

    buckets = buckets(start_dt, end_dt, :day)
    metered = metered_usage(account_id, start_dt, query_end_dt)

    sessions =
      account_id
      |> lifecycle_events(start_dt, query_end_dt)
      |> Enum.chunk_by(& &1.sandbox_id)
      |> sessions(query_end_dt)

    vcpu_sessions =
      sessions
      |> Enum.reject(& &1.bursting?)
      |> Enum.map(&until_metered(&1, metered.first_at))
      |> clip(start_dt, end_dt)

    vcpus =
      vcpu_sessions
      |> bucket_seconds(buckets, & &1.vcpus)
      |> Map.merge(metered.by_bucket.(buckets), fn _index, a, b -> a + b end)
      |> hours(buckets)

    memory =
      sessions
      |> clip(start_dt, end_dt)
      |> bucket_seconds(buckets, fn session -> session.memory_mb / 1024 end)
      |> Map.merge(metered.memory_by_bucket.(buckets), fn _index, a, b -> a + b end)
      |> hours(buckets)

    %{
      vcpu_hours: vcpus.total,
      memory_gib_hours: memory.total,
      dates: Enum.map(buckets, & &1.date),
      values: vcpus.values,
      memory_values: memory.values
    }
  end

  # Billed CPU of bursting sandboxes, by the bucket of the report that
  # metered it, and each metered sandbox's first report.
  defp metered_usage(account_id, start_dt, end_dt) do
    rows =
      ClickHouseRepo.all(
        from(u in UsageEvent,
          where: u.account_id == ^account_id and u.inserted_at >= ^start_dt and u.inserted_at < ^end_dt,
          group_by: [u.sandbox_id, fragment("toStartOfHour(?)", u.inserted_at)],
          select: %{
            sandbox_id: u.sandbox_id,
            hour: fragment("toStartOfHour(?)", u.inserted_at),
            first_at: min(u.inserted_at),
            billed_cpu_ms: sum(u.billed_cpu_ms),
            excess_memory_mib_ms: sum(u.excess_memory_mib_ms)
          }
        )
      )

    %{
      first_at:
        rows
        |> Enum.group_by(& &1.sandbox_id, &to_utc(&1.first_at))
        |> Map.new(fn {id, ats} -> {id, Enum.min(ats, DateTime)} end),
      # CPU-seconds and GiB-seconds per bucket, as `bucket_seconds/3` sums.
      by_bucket: &sum_by_bucket(rows, &1, fn row -> row.billed_cpu_ms / 1000 end),
      memory_by_bucket: &sum_by_bucket(rows, &1, fn row -> row.excess_memory_mib_ms / (1024 * 1000) end)
    }
  end

  defp sum_by_bucket(rows, buckets, amount) do
    Enum.reduce(rows, %{}, fn row, acc ->
      case bucket_index(buckets, to_utc(row.hour)) do
        nil -> acc
        index -> Map.update(acc, index, amount.(row), &(&1 + amount.(row)))
      end
    end)
  end

  defp until_metered(session, first_metered_at) do
    case Map.get(first_metered_at, session.sandbox_id) do
      %DateTime{} = at ->
        %{session | ended_at: Enum.min([session.ended_at, Enum.max([at, session.started_at], DateTime)], DateTime)}

      nil ->
        session
    end
  end

  defp event_count(account_id, event, buckets, prev_start_dt, start_dt, end_dt) do
    timestamps =
      from(e in SandboxEvent,
        where:
          e.account_id == ^account_id and e.event == ^event and e.inserted_at >= ^prev_start_dt and
            e.inserted_at < ^end_dt,
        select: e.inserted_at
      )
      |> ClickHouseRepo.all()
      |> Enum.map(&to_utc/1)

    {current, previous} = Enum.split_with(timestamps, &(DateTime.compare(&1, start_dt) != :lt))
    count = length(current)
    by_bucket = Enum.frequencies_by(current, &bucket_index(buckets, &1))

    %{
      count: count,
      trend: trend(length(previous), count),
      dates: Enum.map(buckets, & &1.date),
      values: buckets |> Enum.with_index() |> Enum.map(fn {_bucket, index} -> Map.get(by_bucket, index, 0) end)
    }
  end

  # Seconds times `amount` of each session, per bucket.
  defp bucket_seconds(sessions, buckets, amount) do
    Enum.reduce(sessions, %{}, fn session, acc ->
      buckets
      |> Enum.with_index()
      |> Enum.reduce(acc, fn {bucket, index}, acc ->
        case overlap_seconds(session, bucket.start, bucket.end) do
          0 -> acc
          seconds -> Map.update(acc, index, seconds * amount.(session), &(&1 + seconds * amount.(session)))
        end
      end)
    end)
  end

  defp hours(by_bucket, buckets) do
    %{
      total: by_bucket |> Map.values() |> Enum.sum() |> Kernel./(3600) |> Float.round(1),
      values:
        buckets
        |> Enum.with_index()
        |> Enum.map(fn {_bucket, index} -> by_bucket |> Map.get(index, 0) |> Kernel./(3600) |> Float.round(1) end)
    }
  end

  defp session_duration(sessions, buckets, prev_start_dt, start_dt, end_dt) do
    ended = Enum.filter(sessions, & &1.stopped?)
    current = Enum.filter(ended, &within?(&1.ended_at, start_dt, end_dt))
    previous = Enum.filter(ended, &within?(&1.ended_at, prev_start_dt, start_dt))
    duration = &DateTime.diff(&1.ended_at, &1.started_at, :millisecond)
    duration_summary(current, previous, buckets, & &1.ended_at, duration, 0)
  end

  # The figures of a duration widget and its chart: the current window's
  # avg and percentiles with their trends, and the same per bucket, with
  # `empty` for buckets without any.
  defp duration_summary(current, previous, buckets, at, duration, empty) do
    current_stats = current |> Enum.map(duration) |> duration_stats()
    previous_stats = previous |> Enum.map(duration) |> duration_stats()
    by_bucket = Enum.group_by(current, &bucket_index(buckets, at.(&1)))

    series =
      buckets
      |> Enum.with_index()
      |> Enum.map(fn {_bucket, index} ->
        case Map.get(by_bucket, index, []) do
          [] -> %{avg: empty, p50: empty, p90: empty, p99: empty}
          entries -> entries |> Enum.map(duration) |> duration_stats()
        end
      end)

    Map.merge(current_stats, %{
      count: length(current),
      trend_avg: trend(previous_stats.avg, current_stats.avg),
      trend_p50: trend(previous_stats.p50, current_stats.p50),
      trend_p90: trend(previous_stats.p90, current_stats.p90),
      trend_p99: trend(previous_stats.p99, current_stats.p99),
      dates: Enum.map(buckets, & &1.date),
      avg_values: Enum.map(series, & &1.avg),
      p50_values: Enum.map(series, & &1.p50),
      p90_values: Enum.map(series, & &1.p90),
      p99_values: Enum.map(series, & &1.p99)
    })
  end

  defp duration_stats([]), do: %{avg: 0, p50: 0, p90: 0, p99: 0}

  defp duration_stats(durations) do
    durations = Enum.sort(durations)

    %{
      avg: div(Enum.sum(durations), length(durations)),
      p50: percentile(durations, 0.5),
      p90: percentile(durations, 0.9),
      p99: percentile(durations, 0.99)
    }
  end

  defp percentile(sorted, quantile), do: Enum.at(sorted, max(ceil(quantile * length(sorted)) - 1, 0))

  # The durations the selected events carry, summarised like session
  # durations, with gaps for buckets without any.
  defp event_durations(events, selected?, buckets, prev_start_dt, start_dt, end_dt) do
    entries = for event <- events, selected?.(event), do: %{at: to_utc(event.inserted_at), ms: event.duration_ms}
    current = Enum.filter(entries, &within?(&1.at, start_dt, end_dt))
    previous = Enum.filter(entries, &within?(&1.at, prev_start_dt, start_dt))
    duration_summary(current, previous, buckets, & &1.at, & &1.ms, nil)
  end

  # Peak guaranteed vCPUs, what the account's limit counts, and memory in
  # use within each bucket.
  defp concurrency(sessions, buckets) do
    %{
      dates: Enum.map(buckets, & &1.date),
      vcpus: peaks(sessions, buckets, & &1.guaranteed_vcpus),
      memory_gb: sessions |> peaks(buckets, & &1.memory_mb) |> Enum.map(&gigabytes/1)
    }
  end

  defp gigabytes(mb), do: Float.round(mb / 1024, 1)

  # The highest sum of `amount` over the intervals overlapping at any one time
  # in each bucket, from a sweep over their starts and ends.
  defp peaks(intervals, buckets, amount) do
    changes =
      intervals
      |> Enum.flat_map(fn interval ->
        [{interval.started_at, 1, amount.(interval)}, {interval.ended_at, 0, -amount.(interval)}]
      end)
      |> Enum.sort_by(fn {at, order, _delta} -> {DateTime.to_unix(at, :microsecond), order} end)

    {peaks, _changes, _level} =
      Enum.reduce(buckets, {[], changes, 0}, fn bucket, {peaks, changes, level} ->
        # An interval that ends as the bucket starts never overlapped it.
        {ending, changes} =
          Enum.split_while(changes, fn {at, order, _} -> order == 0 and not DateTime.after?(at, bucket.start) end)

        level = level + Enum.sum_by(ending, &elem(&1, 2))
        {inside, rest} = Enum.split_while(changes, fn {at, _, _} -> DateTime.before?(at, bucket.end) end)

        {level, peak} =
          Enum.reduce(inside, {level, level}, fn {_at, _order, delta}, {level, peak} ->
            {level + delta, max(peak, level + delta)}
          end)

        {[peak | peaks], rest, level}
      end)

    Enum.reverse(peaks)
  end

  defp lifecycle_events(account_id, from_dt, end_dt) do
    lookback_dt = DateTime.add(from_dt, -@session_lookback_days, :day)

    ClickHouseRepo.all(
      from(e in SandboxEvent,
        where:
          e.account_id == ^account_id and e.event in ^["started", "setup" | Events.stop_events()] and
            e.inserted_at >= ^lookback_dt and e.inserted_at < ^end_dt,
        order_by: [e.sandbox_id, e.inserted_at],
        select: %{
          sandbox_id: e.sandbox_id,
          event: e.event,
          source: e.source,
          boot_source: e.boot_source,
          duration_ms: e.duration_ms,
          vcpus: e.vcpus,
          memory_mb: e.memory_mb,
          guaranteed_cpu_milli: e.guaranteed_cpu_milli,
          inserted_at: e.inserted_at
        }
      )
    )
  end

  defp sessions(by_sandbox, end_dt) do
    open_until = open_until(end_dt)

    Enum.flat_map(by_sandbox, fn events ->
      events |> Enum.filter(&(&1.event in ["started" | Events.stop_events()])) |> pair_sessions(open_until)
    end)
  end

  defp open_until(end_dt) do
    now = DateTime.utc_now()
    if DateTime.before?(now, end_dt), do: now, else: end_dt
  end

  defp pair_sessions(events, open_until) do
    {sessions, open} =
      Enum.reduce(events, {[], nil}, fn event, {sessions, open} ->
        at = to_utc(event.inserted_at)

        case {event.event, open} do
          {"started", nil} -> {sessions, start_session(event, at)}
          {"started", open} -> {[stop_session(open, at) | sessions], start_session(event, at)}
          {_stop, nil} -> {sessions, nil}
          {_stop, open} -> {[stop_session(open, at) | sessions], nil}
        end
      end)

    case open do
      nil -> sessions
      open -> [%{open | ended_at: Enum.max([open.started_at, open_until], DateTime)} | sessions]
    end
  end

  # Events from before guarantees were recorded hold 0: those sandboxes were
  # guaranteed every vCPU.
  defp start_session(event, at) do
    guaranteed = if event.guaranteed_cpu_milli > 0, do: event.guaranteed_cpu_milli, else: event.vcpus * 1000

    %{
      sandbox_id: event.sandbox_id,
      started_at: at,
      ended_at: nil,
      stopped?: false,
      vcpus: event.vcpus,
      guaranteed_vcpus: guaranteed / 1000,
      bursting?: guaranteed < event.vcpus * 1000,
      memory_mb: event.memory_mb
    }
  end

  defp stop_session(session, at), do: %{session | ended_at: at, stopped?: true}

  defp clip(sessions, start_dt, end_dt) do
    for session <- sessions,
        DateTime.before?(session.started_at, end_dt),
        DateTime.after?(session.ended_at, start_dt) do
      %{
        session
        | started_at: Enum.max([session.started_at, start_dt], DateTime),
          ended_at: Enum.min([session.ended_at, end_dt], DateTime)
      }
    end
  end

  defp overlap_seconds(session, start_dt, end_dt) do
    from = Enum.max([session.started_at, start_dt], DateTime)
    to = Enum.min([session.ended_at, end_dt], DateTime)
    max(DateTime.diff(to, from, :second), 0)
  end

  defp within?(at, start_dt, end_dt), do: not DateTime.before?(at, start_dt) and DateTime.before?(at, end_dt)

  defp buckets(start_dt, end_dt, :day) do
    start_dt
    |> DateTime.to_date()
    |> Date.range(DateTime.to_date(end_dt))
    |> Enum.map(fn date ->
      start = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
      %{date: date, start: start, end: DateTime.add(start, 1, :day)}
    end)
  end

  defp buckets(start_dt, end_dt, :hour) do
    floor_end = floor_to_hour(end_dt)

    start_dt
    |> floor_to_hour()
    |> Stream.iterate(&DateTime.add(&1, 1, :hour))
    |> Enum.take_while(&(DateTime.compare(&1, floor_end) != :gt))
    |> Enum.map(&%{date: &1, start: &1, end: DateTime.add(&1, 1, :hour)})
  end

  defp bucket_index(buckets, at) do
    Enum.find_index(buckets, &within?(at, &1.start, &1.end))
  end

  defp floor_to_hour(%DateTime{} = datetime), do: %{datetime | minute: 0, second: 0, microsecond: {0, 0}}

  defp to_utc(%DateTime{} = datetime), do: datetime
  defp to_utc(%NaiveDateTime{} = datetime), do: DateTime.from_naive!(datetime, "Etc/UTC")

  defp trend(previous, current) when is_number(previous) and is_number(current) do
    cond do
      previous == 0 -> 0.0
      current == 0 -> 0.0
      true -> Float.round(current / previous * 100 - 100, 1)
    end
  end
end
