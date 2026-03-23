defmodule Tuist.Shards.Analytics do
  @moduledoc false

  import Ecto.Query

  alias Postgrex.Interval
  alias Tuist.ClickHouseRepo
  alias Tuist.Shards.ShardPlan
  alias Tuist.Shards.ShardRun
  alias Tuist.Tests.Test

  def sharded_run_analytics(project_id, opts \\ []) do
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())

    days_delta = Date.diff(DateTime.to_date(end_datetime), DateTime.to_date(start_datetime))
    date_period = date_period(start_datetime: start_datetime, end_datetime: end_datetime)
    time_bucket = time_bucket_for_date_period(date_period)
    clickhouse_time_bucket = time_bucket_to_clickhouse_interval(time_bucket)

    current_data = sharded_run_count_by_period(project_id, start_datetime, end_datetime, clickhouse_time_bucket)
    current_runs = process_runs_count_data(current_data, start_datetime, end_datetime, date_period)

    previous_count =
      sharded_run_total_count(project_id, DateTime.add(start_datetime, -days_delta, :day), start_datetime)

    current_count = sharded_run_total_count(project_id, start_datetime, end_datetime)

    %{
      trend: trend(previous_value: previous_count, current_value: current_count),
      count: current_count,
      values: Enum.map(current_runs, & &1.count),
      dates: Enum.map(current_runs, & &1.date)
    }
  end

  def shard_count_analytics(project_id, opts \\ []) do
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())

    days_delta = Date.diff(DateTime.to_date(end_datetime), DateTime.to_date(start_datetime))
    date_period = date_period(start_datetime: start_datetime, end_datetime: end_datetime)
    time_bucket = time_bucket_for_date_period(date_period)
    clickhouse_time_bucket = time_bucket_to_clickhouse_interval(time_bucket)

    current_data =
      avg_shard_count_by_period(project_id, start_datetime, end_datetime, clickhouse_time_bucket)

    current_values = process_durations_data(current_data, start_datetime, end_datetime, date_period)

    previous_avg = avg_shard_count_in_range(project_id, DateTime.add(start_datetime, -days_delta, :day), start_datetime)
    current_avg = avg_shard_count_in_range(project_id, start_datetime, end_datetime)

    percentiles = shard_count_percentiles(project_id, start_datetime, end_datetime)

    percentile_by_period =
      shard_count_percentile_by_period(project_id, start_datetime, end_datetime, clickhouse_time_bucket)

    p50_values =
      process_durations_data(
        Enum.map(percentile_by_period, fn row -> %{date: row.date, value: row.p50} end),
        start_datetime,
        end_datetime,
        date_period
      )

    p90_values =
      process_durations_data(
        Enum.map(percentile_by_period, fn row -> %{date: row.date, value: row.p90} end),
        start_datetime,
        end_datetime,
        date_period
      )

    p99_values =
      process_durations_data(
        Enum.map(percentile_by_period, fn row -> %{date: row.date, value: row.p99} end),
        start_datetime,
        end_datetime,
        date_period
      )

    %{
      trend: trend(previous_value: previous_avg, current_value: current_avg),
      total_average: current_avg,
      p50: percentiles.p50,
      p90: percentiles.p90,
      p99: percentiles.p99,
      values: Enum.map(current_values, & &1.value),
      p50_values: Enum.map(p50_values, & &1.value),
      p90_values: Enum.map(p90_values, & &1.value),
      p99_values: Enum.map(p99_values, & &1.value),
      dates: Enum.map(current_values, & &1.date)
    }
  end

  def shard_balance_analytics(project_id, opts \\ []) do
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())

    days_delta = Date.diff(DateTime.to_date(end_datetime), DateTime.to_date(start_datetime))
    date_period = date_period(start_datetime: start_datetime, end_datetime: end_datetime)

    current_sessions = shard_balance_sessions(project_id, start_datetime, end_datetime)

    previous_sessions =
      shard_balance_sessions(project_id, DateTime.add(start_datetime, -days_delta, :day), start_datetime)

    current_avg = compute_average_balance(current_sessions)
    previous_avg = compute_average_balance(previous_sessions)

    current_percentiles = compute_balance_percentiles(current_sessions)
    bucketed = bucket_sessions_by_period(current_sessions, start_datetime, end_datetime, date_period)

    avg_values = process_bucketed_balance(bucketed, &compute_average_balance/1)
    p50_values = process_bucketed_balance(bucketed, &compute_percentile_balance(&1, 0.50))
    p90_values = process_bucketed_balance(bucketed, &compute_percentile_balance(&1, 0.90))
    p99_values = process_bucketed_balance(bucketed, &compute_percentile_balance(&1, 0.99))

    %{
      trend: trend(previous_value: previous_avg, current_value: current_avg),
      total_average: current_avg,
      p50: current_percentiles.p50,
      p90: current_percentiles.p90,
      p99: current_percentiles.p99,
      values: Enum.map(avg_values, & &1.value),
      p50_values: Enum.map(p50_values, & &1.value),
      p90_values: Enum.map(p90_values, & &1.value),
      p99_values: Enum.map(p99_values, & &1.value),
      dates: Enum.map(avg_values, & &1.date)
    }
  end

  defp shard_count_percentiles(project_id, start_datetime, end_datetime) do
    result =
      ClickHouseRepo.one(
        from(s in ShardPlan,
          where: s.project_id == ^project_id,
          where: s.inserted_at >= ^start_datetime,
          where: s.inserted_at <= ^end_datetime,
          select: %{
            p50: fragment("round(quantile(0.50)(?), 1)", s.shard_count),
            p90: fragment("round(quantile(0.90)(?), 1)", s.shard_count),
            p99: fragment("round(quantile(0.99)(?), 1)", s.shard_count)
          }
        )
      )

    case result do
      %{p50: p50, p90: p90, p99: p99} -> %{p50: p50 || 0, p90: p90 || 0, p99: p99 || 0}
      _ -> %{p50: 0, p90: 0, p99: 0}
    end
  end

  defp shard_count_percentile_by_period(project_id, start_datetime, end_datetime, time_bucket) do
    date_format = get_clickhouse_date_format(time_bucket)

    ClickHouseRepo.all(
      from(s in ShardPlan,
        where: s.project_id == ^project_id,
        where: s.inserted_at >= ^start_datetime,
        where: s.inserted_at <= ^end_datetime,
        group_by: fragment("formatDateTime(?, ?)", s.inserted_at, ^date_format),
        select: %{
          date: fragment("formatDateTime(?, ?)", s.inserted_at, ^date_format),
          p50: fragment("round(quantile(0.50)(?), 1)", s.shard_count),
          p90: fragment("round(quantile(0.90)(?), 1)", s.shard_count),
          p99: fragment("round(quantile(0.99)(?), 1)", s.shard_count)
        },
        order_by: fragment("formatDateTime(?, ?)", s.inserted_at, ^date_format)
      )
    )
  end

  defp shard_balance_sessions(project_id, start_datetime, end_datetime) do
    ClickHouseRepo.all(
      from(t in Test,
        where: t.project_id == ^project_id,
        where: not is_nil(t.shard_plan_id),
        where: t.ran_at >= ^start_datetime,
        where: t.ran_at <= ^end_datetime,
        group_by: t.shard_plan_id,
        having: count() > 1,
        select: %{
          plan_id: t.shard_plan_id,
          balance:
            fragment(
              "if(avg(?) > 0, greatest(0, 1 - (stddevPop(?) / avg(?))), 1)",
              t.duration,
              t.duration,
              t.duration
            ),
          ran_at: max(t.ran_at)
        }
      )
    )
  end

  defp compute_average_balance([]), do: 0
  defp compute_average_balance(nil), do: 0

  defp compute_average_balance(sessions) do
    sessions
    |> Enum.map(& &1.balance)
    |> Enum.sum()
    |> then(&(&1 / length(sessions) * 100))
    |> round()
  end

  defp compute_percentile_balance([], _quantile), do: 0

  defp compute_percentile_balance(sessions, quantile) do
    sorted = sessions |> Enum.map(& &1.balance) |> Enum.sort()
    index = min(round(quantile * length(sorted)), length(sorted) - 1)

    sorted
    |> Enum.at(index)
    |> Kernel.*(100)
    |> round()
  end

  defp compute_balance_percentiles([]), do: %{p50: 0, p90: 0, p99: 0}

  defp compute_balance_percentiles(sessions) do
    %{
      p50: compute_percentile_balance(sessions, 0.50),
      p90: compute_percentile_balance(sessions, 0.90),
      p99: compute_percentile_balance(sessions, 0.99)
    }
  end

  defp bucket_sessions_by_period(sessions, start_datetime, end_datetime, date_period) do
    sessions_map =
      Enum.group_by(sessions, fn session -> normalise_date(session.ran_at, date_period) end)

    date_period
    |> date_range_for_date_period(start_datetime: start_datetime, end_datetime: end_datetime)
    |> Enum.map(fn date ->
      normalized_date = normalise_date(date, date_period)
      bucket_sessions = Map.get(sessions_map, normalized_date, [])
      %{date: date, sessions: bucket_sessions}
    end)
  end

  defp process_bucketed_balance(bucketed, compute_fn) do
    Enum.map(bucketed, fn %{date: date, sessions: sessions} ->
      %{date: date, value: compute_fn.(sessions)}
    end)
  end

  defp sharded_run_count_by_period(project_id, start_datetime, end_datetime, time_bucket) do
    date_format = get_clickhouse_date_format(time_bucket)

    ClickHouseRepo.all(
      from(t in Test,
        hints: ["FINAL"],
        where: t.project_id == ^project_id,
        where: not is_nil(t.shard_plan_id),
        where: t.ran_at >= ^start_datetime,
        where: t.ran_at <= ^end_datetime,
        group_by: fragment("formatDateTime(?, ?)", t.ran_at, ^date_format),
        select: %{
          date: fragment("formatDateTime(?, ?)", t.ran_at, ^date_format),
          count: fragment("uniq(?)", t.shard_plan_id)
        },
        order_by: fragment("formatDateTime(?, ?)", t.ran_at, ^date_format)
      )
    )
  end

  defp sharded_run_total_count(project_id, start_datetime, end_datetime) do
    ClickHouseRepo.one(
      from(t in Test,
        hints: ["FINAL"],
        where: t.project_id == ^project_id,
        where: not is_nil(t.shard_plan_id),
        where: t.ran_at >= ^start_datetime,
        where: t.ran_at <= ^end_datetime,
        select: fragment("uniq(?)", t.shard_plan_id)
      )
    ) || 0
  end

  defp avg_shard_count_by_period(project_id, start_datetime, end_datetime, time_bucket) do
    date_format = get_clickhouse_date_format(time_bucket)

    ClickHouseRepo.all(
      from(s in ShardPlan,
        where: s.project_id == ^project_id,
        where: s.inserted_at >= ^start_datetime,
        where: s.inserted_at <= ^end_datetime,
        group_by: fragment("formatDateTime(?, ?)", s.inserted_at, ^date_format),
        select: %{
          date: fragment("formatDateTime(?, ?)", s.inserted_at, ^date_format),
          value: fragment("round(avg(?), 1)", s.shard_count)
        },
        order_by: fragment("formatDateTime(?, ?)", s.inserted_at, ^date_format)
      )
    )
  end

  defp avg_shard_count_in_range(project_id, start_datetime, end_datetime) do
    ClickHouseRepo.one(
      from(s in ShardPlan,
        where: s.project_id == ^project_id,
        where: s.inserted_at >= ^start_datetime,
        where: s.inserted_at <= ^end_datetime,
        select: fragment("round(avg(?), 1)", s.shard_count)
      )
    ) || 0
  end

  def trend(opts) do
    previous_value = Keyword.get(opts, :previous_value)
    current_value = Keyword.get(opts, :current_value)

    case {previous_value, current_value} do
      {0, _} ->
        0.0

      {_, 0} ->
        0.0

      {+0.0, _} ->
        0.0

      {_, +0.0} ->
        0.0

      {previous_value, current_value} ->
        Float.round(current_value / previous_value * 100, 1) - 100.0
    end
  end

  defp date_period(opts) do
    start_datetime = Keyword.get(opts, :start_datetime)
    end_datetime = Keyword.get(opts, :end_datetime)
    days_delta = Date.diff(DateTime.to_date(end_datetime), DateTime.to_date(start_datetime))

    cond do
      days_delta <= 1 -> :hour
      days_delta >= 60 -> :month
      true -> :day
    end
  end

  defp time_bucket_for_date_period(:hour), do: %Interval{secs: 3600}
  defp time_bucket_for_date_period(:day), do: %Interval{days: 1}
  defp time_bucket_for_date_period(:month), do: %Interval{months: 1}

  defp time_bucket_to_clickhouse_interval(%Interval{secs: 3600}), do: "1 hour"
  defp time_bucket_to_clickhouse_interval(%Interval{days: 1}), do: "1 day"
  defp time_bucket_to_clickhouse_interval(%Interval{months: 1}), do: "1 month"

  defp date_range_for_date_period(:hour, opts) do
    start_datetime = DateTime.truncate(Keyword.fetch!(opts, :start_datetime), :second)
    end_datetime = DateTime.truncate(Keyword.fetch!(opts, :end_datetime), :second)

    start_datetime
    |> Stream.iterate(&DateTime.add(&1, 1, :hour))
    |> Enum.take_while(&(DateTime.compare(&1, end_datetime) != :gt))
  end

  defp date_range_for_date_period(:month, opts) do
    start_datetime = Keyword.get(opts, :start_datetime)
    end_datetime = Keyword.get(opts, :end_datetime)

    start_datetime
    |> DateTime.to_date()
    |> Date.beginning_of_month()
    |> Date.range(Date.beginning_of_month(DateTime.to_date(end_datetime)))
    |> Enum.filter(&(&1.day == 1))
  end

  defp date_range_for_date_period(:day, opts) do
    start_datetime = Keyword.get(opts, :start_datetime)
    end_datetime = Keyword.get(opts, :end_datetime)

    start_datetime
    |> DateTime.to_date()
    |> Date.range(DateTime.to_date(end_datetime))
    |> Enum.to_list()
  end

  defp normalise_date(date_input, :hour) do
    case date_input do
      %DateTime{} = dt ->
        Timex.format!(dt, "%Y-%m-%d %H:00", :strftime)

      %NaiveDateTime{} = dt ->
        Timex.format!(dt, "%Y-%m-%d %H:00", :strftime)

      date_string when is_binary(date_string) ->
        date_string
        |> String.slice(0, 13)
        |> Kernel.<>(":00")

      %Date{} = d ->
        Timex.format!(d, "%Y-%m-%d", :strftime) <> " 00:00"
    end
  end

  defp normalise_date(date_input, date_period) do
    date =
      case date_input do
        %DateTime{} = dt ->
          DateTime.to_date(dt)

        %NaiveDateTime{} = dt ->
          NaiveDateTime.to_date(dt)

        date_string when is_binary(date_string) ->
          case Date.from_iso8601(date_string) do
            {:ok, date} -> date
            {:error, :invalid_format} -> Date.from_iso8601!(date_string <> "-01")
          end

        %Date{} = d ->
          d
      end

    case date_period do
      :day -> date
      :month -> Date.beginning_of_month(date)
    end
  end

  defp process_runs_count_data(runs_data, start_datetime, end_datetime, date_period) do
    runs_map =
      case runs_data do
        data when is_list(data) ->
          Map.new(data, &{normalise_date(&1.date, date_period), &1.count})

        _ ->
          %{}
      end

    date_period
    |> date_range_for_date_period(start_datetime: start_datetime, end_datetime: end_datetime)
    |> Enum.map(fn date ->
      normalized_date = normalise_date(date, date_period)
      count = Map.get(runs_map, normalized_date, 0)
      %{date: date, count: count}
    end)
  end

  defp process_durations_data(durations_data, start_datetime, end_datetime, date_period) do
    durations_map =
      case durations_data do
        data when is_list(data) ->
          Map.new(data, &{normalise_date(&1.date, date_period), &1.value})

        _ ->
          %{}
      end

    date_period
    |> date_range_for_date_period(start_datetime: start_datetime, end_datetime: end_datetime)
    |> Enum.map(fn date ->
      normalized_date = normalise_date(date, date_period)
      duration = Map.get(durations_map, normalized_date)

      %{
        date: date,
        value:
          case duration do
            nil -> 0
            duration when is_float(duration) -> duration
            _ -> Decimal.to_float(duration)
          end
      }
    end)
  end

  defp get_clickhouse_date_format("1 hour"), do: "%Y-%m-%d %H:00"
  defp get_clickhouse_date_format("1 day"), do: "%Y-%m-%d"
  defp get_clickhouse_date_format("1 month"), do: "%Y-%m"
  defp get_clickhouse_date_format(_), do: "%Y-%m-%d"

  def shard_metrics(test_run_id) when is_binary(test_run_id) do
    ClickHouseRepo.all(
      from(sr in ShardRun,
        where: sr.test_run_id == ^test_run_id,
        select: %{
          shard_index: sr.shard_index,
          actual_duration_ms: sr.duration,
          status: sr.status,
          ran_at: sr.ran_at
        }
      )
    )
  end

  def shard_metrics(_), do: []
end
