defmodule Tuist.Tests.Analytics do
  @moduledoc """
  Module for test-related analytics.
  """
  import Ecto.Query

  alias Postgrex.Interval
  alias Tuist.ClickHouseRepo
  alias Tuist.CommandEvents
  alias Tuist.CommandEvents.Event
  alias Tuist.Tests.Test
  alias Tuist.Tests.TestCase
  alias Tuist.Tests.TestCaseEvent
  alias Tuist.Tests.TestCaseRun

  def runs_analytics(project_id, name, opts) do
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())

    days_delta = Date.diff(DateTime.to_date(end_datetime), DateTime.to_date(start_datetime))
    date_period = date_period(start_datetime: start_datetime, end_datetime: end_datetime)
    time_bucket = time_bucket_for_date_period(date_period)
    clickhouse_time_bucket = time_bucket_to_clickhouse_interval(time_bucket)

    current_runs_data =
      CommandEvents.run_count(
        project_id,
        start_datetime,
        end_datetime,
        date_period,
        clickhouse_time_bucket,
        name,
        opts
      )

    current_runs = process_runs_count_data(current_runs_data, start_datetime, end_datetime, date_period)

    previous_runs_count =
      runs_total_count(project_id, DateTime.add(start_datetime, -days_delta, :day), start_datetime, name, opts)

    current_runs_count = runs_total_count(project_id, start_datetime, end_datetime, name, opts)

    %{
      trend:
        trend(
          previous_value: previous_runs_count,
          current_value: current_runs_count
        ),
      count: current_runs_count,
      values: Enum.map(current_runs, & &1.count),
      dates: Enum.map(current_runs, & &1.date)
    }
  end

  defp runs_total_count(project_id, start_datetime, end_datetime, name, opts) do
    CommandEvents.run_analytics(
      project_id,
      start_datetime,
      end_datetime,
      Keyword.put(opts, :name, name)
    )[:count] || 0
  end

  def runs_duration_analytics(name, opts) do
    project_id = Keyword.get(opts, :project_id)
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())

    days_delta = Date.diff(DateTime.to_date(end_datetime), DateTime.to_date(start_datetime))
    date_period = date_period(start_datetime: start_datetime, end_datetime: end_datetime)
    time_bucket = time_bucket_for_date_period(date_period)
    clickhouse_time_bucket = time_bucket_to_clickhouse_interval(time_bucket)

    previous_period_runs_aggregated_analytics =
      CommandEvents.run_analytics(
        project_id,
        DateTime.add(start_datetime, -days_delta, :day),
        start_datetime,
        Keyword.put(opts, :name, name)
      )

    previous_period_total_average_duration =
      previous_period_runs_aggregated_analytics[:average_duration] || 0

    current_period_runs_data =
      CommandEvents.run_analytics(
        project_id,
        start_datetime,
        end_datetime,
        Keyword.put(opts, :name, name)
      )

    total_average_duration = current_period_runs_data[:average_duration] || 0

    average_durations_data =
      CommandEvents.run_average_durations(
        project_id,
        start_datetime,
        end_datetime,
        date_period,
        clickhouse_time_bucket,
        name,
        opts
      )

    average_durations =
      process_durations_data(average_durations_data, start_datetime, end_datetime, date_period)

    %{
      trend:
        trend(
          previous_value: previous_period_total_average_duration,
          current_value: total_average_duration
        ),
      total_average_duration: total_average_duration,
      average_durations: average_durations,
      dates: Enum.map(average_durations, & &1.date),
      values: Enum.map(average_durations, & &1.value)
    }
  end

  def test_run_analytics(project_id, opts \\ []) do
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())

    days_delta = Date.diff(DateTime.to_date(end_datetime), DateTime.to_date(start_datetime))
    date_period = date_period(start_datetime: start_datetime, end_datetime: end_datetime)
    time_bucket = time_bucket_for_date_period(date_period)
    clickhouse_time_bucket = time_bucket_to_clickhouse_interval(time_bucket)

    current_runs_data =
      test_run_count(
        project_id,
        start_datetime,
        end_datetime,
        date_period,
        clickhouse_time_bucket,
        opts
      )

    current_runs = process_runs_count_data(current_runs_data, start_datetime, end_datetime, date_period)

    previous_runs_count =
      test_run_total_count(project_id, DateTime.add(start_datetime, -days_delta, :day), start_datetime, opts)

    current_runs_count = test_run_total_count(project_id, start_datetime, end_datetime, opts)

    %{
      trend:
        trend(
          previous_value: previous_runs_count,
          current_value: current_runs_count
        ),
      count: current_runs_count,
      values: Enum.map(current_runs, & &1.count),
      dates: Enum.map(current_runs, & &1.date)
    }
  end

  defp test_run_count(project_id, start_datetime, end_datetime, _date_period, time_bucket, opts) do
    date_format = get_clickhouse_date_format(time_bucket)

    from(t in Test,
      where: t.project_id == ^project_id,
      where: t.ran_at >= ^start_datetime,
      where: t.ran_at <= ^end_datetime,
      group_by: fragment("formatDateTime(?, ?)", t.ran_at, ^date_format),
      select: %{
        date: fragment("formatDateTime(?, ?)", t.ran_at, ^date_format),
        count: count(t.id)
      },
      order_by: fragment("formatDateTime(?, ?)", t.ran_at, ^date_format)
    )
    |> apply_test_run_filters(opts)
    |> ClickHouseRepo.all()
  end

  defp test_run_total_count(project_id, start_datetime, end_datetime, opts) do
    from(t in Test,
      where: t.project_id == ^project_id,
      where: t.ran_at >= ^start_datetime,
      where: t.ran_at <= ^end_datetime,
      select: count(t.id)
    )
    |> apply_test_run_filters(opts)
    |> ClickHouseRepo.one() || 0
  end

  defp apply_test_run_filters(query, opts) do
    query
    |> apply_test_is_ci_filter(Keyword.get(opts, :is_ci))
    |> apply_test_is_flaky_filter(Keyword.get(opts, :is_flaky))
    |> apply_test_status_filter(Keyword.get(opts, :status))
  end

  defp apply_test_is_ci_filter(query, nil), do: query
  defp apply_test_is_ci_filter(query, true), do: where(query, [t], t.is_ci == true)
  defp apply_test_is_ci_filter(query, false), do: where(query, [t], t.is_ci == false)

  defp apply_test_is_flaky_filter(query, nil), do: query
  defp apply_test_is_flaky_filter(query, true), do: where(query, [t], t.is_flaky == true)
  defp apply_test_is_flaky_filter(query, false), do: where(query, [t], t.is_flaky == false)

  defp apply_test_status_filter(query, nil), do: query
  defp apply_test_status_filter(query, "failure"), do: where(query, [t], t.status == "failure")
  defp apply_test_status_filter(query, "success"), do: where(query, [t], t.status == "success")

  @doc """
  Returns analytics for quarantined tests count over time for a project.
  This computes the number of quarantined tests at each time bucket by
  tracking quarantine/unquarantine events from the test_case_events table.
  """
  def quarantined_tests_analytics(project_id, opts \\ []) do
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())

    date_period = date_period(start_datetime: start_datetime, end_datetime: end_datetime)
    time_bucket = time_bucket_for_date_period(date_period)
    clickhouse_time_bucket = time_bucket_to_clickhouse_interval(time_bucket)

    date_format = get_clickhouse_date_format(clickhouse_time_bucket)

    project_test_case_ids_subquery =
      from(tc in TestCase,
        where: tc.project_id == ^project_id,
        group_by: tc.id,
        select: tc.id
      )

    events_in_period =
      ClickHouseRepo.all(
        from(e in TestCaseEvent,
          where: e.test_case_id in subquery(project_test_case_ids_subquery),
          where: e.event_type in ["quarantined", "unquarantined"],
          where: e.inserted_at >= ^start_datetime,
          where: e.inserted_at <= ^end_datetime,
          group_by: fragment("formatDateTime(?, ?)", e.inserted_at, ^date_format),
          select: %{
            date: fragment("formatDateTime(?, ?)", e.inserted_at, ^date_format),
            quarantined: count(fragment("CASE WHEN ? = 'quarantined' THEN 1 END", e.event_type)),
            unquarantined: count(fragment("CASE WHEN ? = 'unquarantined' THEN 1 END", e.event_type))
          },
          order_by: fragment("formatDateTime(?, ?)", e.inserted_at, ^date_format)
        )
      )

    initial_count = quarantined_count_before(project_id, start_datetime)

    dates = date_range_for_date_period(date_period, start_datetime: start_datetime, end_datetime: end_datetime)

    events_map =
      Map.new(events_in_period, fn event ->
        {normalise_date(event.date, date_period), {event.quarantined, event.unquarantined}}
      end)

    {values, _} =
      Enum.map_reduce(dates, initial_count, fn date, running_count ->
        normalized = normalise_date(date, date_period)
        {quarantined, unquarantined} = Map.get(events_map, normalized, {0, 0})
        new_count = max(running_count + quarantined - unquarantined, 0)
        {new_count, new_count}
      end)

    current_count = quarantined_count_at(project_id, end_datetime)

    %{
      count: current_count,
      values: values,
      dates: dates
    }
  end

  defp quarantined_count_before(project_id, datetime) do
    project_test_case_ids_subquery =
      from(tc in TestCase,
        where: tc.project_id == ^project_id,
        group_by: tc.id,
        select: tc.id
      )

    events_query =
      from(e in TestCaseEvent,
        where: e.test_case_id in subquery(project_test_case_ids_subquery),
        where: e.event_type in ["quarantined", "unquarantined"],
        where: e.inserted_at < ^datetime,
        select: %{
          quarantined: count(fragment("CASE WHEN ? = 'quarantined' THEN 1 END", e.event_type)),
          unquarantined: count(fragment("CASE WHEN ? = 'unquarantined' THEN 1 END", e.event_type))
        }
      )

    result = ClickHouseRepo.one(events_query)

    if result do
      max((result.quarantined || 0) - (result.unquarantined || 0), 0)
    else
      0
    end
  end

  defp quarantined_count_at(project_id, datetime) do
    latest_test_case_subquery =
      from(test_case in TestCase,
        where: test_case.project_id == ^project_id,
        where: test_case.inserted_at <= ^datetime,
        group_by: test_case.id,
        select: %{id: test_case.id, max_inserted_at: max(test_case.inserted_at)}
      )

    query =
      from(test_case in TestCase,
        join: latest in subquery(latest_test_case_subquery),
        on: test_case.id == latest.id and test_case.inserted_at == latest.max_inserted_at,
        where: test_case.is_quarantined == true,
        select: count(test_case.id)
      )

    ClickHouseRepo.one(query) || 0
  end

  def test_run_duration_analytics(project_id, opts \\ []) do
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())

    days_delta = Date.diff(DateTime.to_date(end_datetime), DateTime.to_date(start_datetime))
    date_period = date_period(start_datetime: start_datetime, end_datetime: end_datetime)
    time_bucket = time_bucket_for_date_period(date_period)
    clickhouse_time_bucket = time_bucket_to_clickhouse_interval(time_bucket)

    previous_period_total_average_duration =
      test_run_aggregated_duration(project_id, DateTime.add(start_datetime, -days_delta, :day), start_datetime, opts)

    current_period_total_average_duration =
      test_run_aggregated_duration(project_id, start_datetime, end_datetime, opts)

    current_period_percentiles =
      test_run_duration_percentiles(project_id, start_datetime, end_datetime, opts)

    average_durations_data =
      test_run_average_durations(
        project_id,
        start_datetime,
        end_datetime,
        date_period,
        clickhouse_time_bucket,
        opts
      )

    percentile_durations_data =
      test_run_percentile_durations(
        project_id,
        start_datetime,
        end_datetime,
        date_period,
        clickhouse_time_bucket,
        opts
      )

    average_durations =
      process_durations_data(average_durations_data, start_datetime, end_datetime, date_period)

    p50_durations =
      process_durations_data(
        Enum.map(percentile_durations_data, fn row -> %{date: row.date, value: row.p50} end),
        start_datetime,
        end_datetime,
        date_period
      )

    p90_durations =
      process_durations_data(
        Enum.map(percentile_durations_data, fn row -> %{date: row.date, value: row.p90} end),
        start_datetime,
        end_datetime,
        date_period
      )

    p99_durations =
      process_durations_data(
        Enum.map(percentile_durations_data, fn row -> %{date: row.date, value: row.p99} end),
        start_datetime,
        end_datetime,
        date_period
      )

    %{
      trend:
        trend(
          previous_value: previous_period_total_average_duration,
          current_value: current_period_total_average_duration
        ),
      total_average_duration: current_period_total_average_duration,
      p50: current_period_percentiles.p50,
      p90: current_period_percentiles.p90,
      p99: current_period_percentiles.p99,
      average_durations: average_durations,
      dates: Enum.map(average_durations, & &1.date),
      values: Enum.map(average_durations, & &1.value),
      p50_values: Enum.map(p50_durations, & &1.value),
      p90_values: Enum.map(p90_durations, & &1.value),
      p99_values: Enum.map(p99_durations, & &1.value)
    }
  end

  defp test_run_aggregated_duration(project_id, start_datetime, end_datetime, opts) do
    is_ci = Keyword.get(opts, :is_ci)

    query =
      from(t in Test,
        where: t.project_id == ^project_id,
        where: t.ran_at >= ^start_datetime,
        where: t.ran_at <= ^end_datetime,
        select: avg(t.duration)
      )

    query =
      case is_ci do
        nil -> query
        true -> where(query, [t], t.is_ci == true)
        false -> where(query, [t], t.is_ci == false)
      end

    result = ClickHouseRepo.one(query)

    case result do
      nil -> 0.0
      avg when is_float(avg) -> avg
      avg -> avg * 1.0
    end
  end

  defp test_run_average_durations(project_id, start_datetime, end_datetime, _date_period, time_bucket, opts) do
    date_format = get_clickhouse_date_format(time_bucket)

    is_ci = Keyword.get(opts, :is_ci)

    query =
      from(t in Test,
        where: t.project_id == ^project_id,
        where: t.ran_at >= ^start_datetime,
        where: t.ran_at <= ^end_datetime,
        group_by: fragment("formatDateTime(?, ?)", t.ran_at, ^date_format),
        select: %{
          date: fragment("formatDateTime(?, ?)", t.ran_at, ^date_format),
          value: avg(t.duration)
        },
        order_by: fragment("formatDateTime(?, ?)", t.ran_at, ^date_format)
      )

    query =
      case is_ci do
        nil -> query
        true -> where(query, [t], t.is_ci == true)
        false -> where(query, [t], t.is_ci == false)
      end

    ClickHouseRepo.all(query)
  end

  defp test_run_duration_percentiles(project_id, start_datetime, end_datetime, opts) do
    is_ci = Keyword.get(opts, :is_ci)

    query =
      from(t in Test,
        where: t.project_id == ^project_id,
        where: t.ran_at >= ^start_datetime,
        where: t.ran_at <= ^end_datetime,
        select: %{
          p50: fragment("quantile(0.50)(?)", t.duration),
          p90: fragment("quantile(0.90)(?)", t.duration),
          p99: fragment("quantile(0.99)(?)", t.duration)
        }
      )

    query =
      case is_ci do
        nil -> query
        true -> where(query, [t], t.is_ci == true)
        false -> where(query, [t], t.is_ci == false)
      end

    result = ClickHouseRepo.one(query)

    case result do
      %{p50: p50, p90: p90, p99: p99} ->
        %{
          p50: normalize_percentile(p50),
          p90: normalize_percentile(p90),
          p99: normalize_percentile(p99)
        }

      _ ->
        %{p50: 0.0, p90: 0.0, p99: 0.0}
    end
  end

  defp test_run_percentile_durations(project_id, start_datetime, end_datetime, _date_period, time_bucket, opts) do
    date_format = get_clickhouse_date_format(time_bucket)

    is_ci = Keyword.get(opts, :is_ci)

    query =
      from(t in Test,
        where: t.project_id == ^project_id,
        where: t.ran_at >= ^start_datetime,
        where: t.ran_at <= ^end_datetime,
        group_by: fragment("formatDateTime(?, ?)", t.ran_at, ^date_format),
        select: %{
          date: fragment("formatDateTime(?, ?)", t.ran_at, ^date_format),
          p50: fragment("quantile(0.5)(?)", t.duration),
          p90: fragment("quantile(0.9)(?)", t.duration),
          p99: fragment("quantile(0.99)(?)", t.duration)
        },
        order_by: fragment("formatDateTime(?, ?)", t.ran_at, ^date_format)
      )

    query =
      case is_ci do
        nil -> query
        true -> where(query, [t], t.is_ci == true)
        false -> where(query, [t], t.is_ci == false)
      end

    query
    |> ClickHouseRepo.all()
    |> Enum.map(fn row ->
      %{
        date: row.date,
        p50: row.p50 || 0,
        p90: row.p90 || 0,
        p99: row.p99 || 0
      }
    end)
  end

  @doc """
  Gets test run metrics for a specific test run.

  Returns a map with:
  - total_count: Total number of test cases
  - failed_count: Number of failed test cases
  - flaky_count: Number of flaky test cases
  - avg_duration: Average test case duration in milliseconds
  """
  def get_test_run_metrics(test_run_id) do
    query =
      from t in TestCaseRun,
        where: t.test_run_id == ^test_run_id,
        select: %{
          total_count: fragment("coalesce(count(?), 0)", t.id),
          failed_count: fragment("coalesce(countIf(? = 'failure'), 0)", t.status),
          flaky_count: fragment("coalesce(countIf(?), 0)", t.is_flaky),
          avg_duration: fragment("ifNotFinite(round(avg(?)), 0)", t.duration)
        }

    ClickHouseRepo.one(query) || %{total_count: 0, failed_count: 0, flaky_count: 0, avg_duration: 0}
  end

  @doc """
  Fetches metrics for multiple test runs with precomputed values.

  Returns a list of maps with:
  - test_run_id: The test run ID
  - total_tests: Total number of test cases
  - cache_hit_rate: Cache hit rate as a string (e.g., "50 %")
  - skipped_tests: Number of skipped test targets
  - ran_tests: Number of test cases that actually ran
  """
  def test_runs_metrics(test_runs) when is_list(test_runs) do
    test_run_ids = Enum.map(test_runs, & &1.id)

    test_case_counts =
      ClickHouseRepo.all(
        from(t in TestCaseRun,
          where: t.test_run_id in ^test_run_ids,
          group_by: t.test_run_id,
          select: %{
            test_run_id: t.test_run_id,
            total_count: count(t.id)
          }
        )
      )

    event_data =
      ClickHouseRepo.all(
        from(e in Event,
          where: e.test_run_id in ^test_run_ids,
          select: %{
            test_run_id: e.test_run_id,
            cacheable_targets_count: e.cacheable_targets_count,
            local_cache_hits_count: e.local_cache_hits_count,
            remote_cache_hits_count: e.remote_cache_hits_count,
            local_test_hits_count: e.local_test_hits_count,
            remote_test_hits_count: e.remote_test_hits_count
          }
        )
      )

    event_data_map = Map.new(event_data, &{&1.test_run_id, &1})

    Enum.map(test_case_counts, fn test_case_count ->
      test_run_id = test_case_count.test_run_id
      total_count = test_case_count.total_count
      event_info = Map.get(event_data_map, test_run_id, %{})

      cacheable_targets = Map.get(event_info, :cacheable_targets_count) || 0
      local_cache_hits = Map.get(event_info, :local_cache_hits_count) || 0
      remote_cache_hits = Map.get(event_info, :remote_cache_hits_count) || 0
      total_cache_hits = local_cache_hits + remote_cache_hits

      cache_hit_rate =
        if cacheable_targets == 0 do
          "0 %"
        else
          "#{(total_cache_hits / cacheable_targets * 100) |> Float.floor() |> round()} %"
        end

      local_test_hits = Map.get(event_info, :local_test_hits_count) || 0
      remote_test_hits = Map.get(event_info, :remote_test_hits_count) || 0
      skipped_tests = local_test_hits + remote_test_hits
      ran_tests = total_count - skipped_tests

      %{
        test_run_id: test_run_id,
        total_tests: total_count,
        cache_hit_rate: cache_hit_rate,
        skipped_tests: skipped_tests,
        ran_tests: ran_tests
      }
    end)
  end

  @doc """
  Gets test case run analytics for a project over a time period.
  Returns count of test case runs with trend data for charts.

  ## Options
    * `:start_date` - Start date for the analytics period (default: 30 days ago)
    * `:end_date` - End date for the analytics period (default: today)
    * `:is_ci` - Filter by CI runs (true/false/nil for all)
    * `:status` - Filter by status ("success"/"failure"/"skipped"/nil for all)
  """
  def test_case_run_analytics(project_id, opts \\ []) do
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())

    days_delta = Date.diff(DateTime.to_date(end_datetime), DateTime.to_date(start_datetime))
    date_period = date_period(start_datetime: start_datetime, end_datetime: end_datetime)
    time_bucket = time_bucket_for_date_period(date_period)
    clickhouse_time_bucket = time_bucket_to_clickhouse_interval(time_bucket)

    current_runs_data =
      test_case_run_count(
        project_id,
        start_datetime,
        end_datetime,
        date_period,
        clickhouse_time_bucket,
        opts
      )

    current_runs = process_runs_count_data(current_runs_data, start_datetime, end_datetime, date_period)

    previous_runs_count =
      test_case_run_total_count(project_id, DateTime.add(start_datetime, -days_delta, :day), start_datetime, opts)

    current_runs_count = test_case_run_total_count(project_id, start_datetime, end_datetime, opts)

    %{
      trend:
        trend(
          previous_value: previous_runs_count,
          current_value: current_runs_count
        ),
      count: current_runs_count,
      values: Enum.map(current_runs, & &1.count),
      dates: Enum.map(current_runs, & &1.date)
    }
  end

  defp test_case_run_count(project_id, start_datetime, end_datetime, _date_period, time_bucket, opts) do
    date_format = get_clickhouse_date_format(time_bucket)

    is_ci = Keyword.get(opts, :is_ci)
    status = Keyword.get(opts, :status)

    query =
      from(tcr in TestCaseRun,
        where: tcr.project_id == ^project_id,
        where: tcr.inserted_at >= ^start_datetime,
        where: tcr.inserted_at <= ^end_datetime,
        group_by: fragment("formatDateTime(?, ?)", tcr.inserted_at, ^date_format),
        select: %{
          date: fragment("formatDateTime(?, ?)", tcr.inserted_at, ^date_format),
          count: count(tcr.id)
        },
        order_by: fragment("formatDateTime(?, ?)", tcr.inserted_at, ^date_format)
      )

    query
    |> apply_is_ci_filter(is_ci)
    |> apply_status_filter(status)
    |> ClickHouseRepo.all()
  end

  defp test_case_run_total_count(project_id, start_datetime, end_datetime, opts) do
    is_ci = Keyword.get(opts, :is_ci)
    status = Keyword.get(opts, :status)

    from(tcr in TestCaseRun,
      where: tcr.project_id == ^project_id,
      where: tcr.inserted_at >= ^start_datetime,
      where: tcr.inserted_at <= ^end_datetime,
      select: count(tcr.id)
    )
    |> apply_is_ci_filter(is_ci)
    |> apply_status_filter(status)
    |> ClickHouseRepo.one() || 0
  end

  defp apply_is_ci_filter(query, nil), do: query
  defp apply_is_ci_filter(query, true), do: where(query, [tcr], tcr.is_ci == true)
  defp apply_is_ci_filter(query, false), do: where(query, [tcr], tcr.is_ci == false)

  defp apply_status_filter(query, nil), do: query
  defp apply_status_filter(query, "failure"), do: where(query, [tcr], tcr.status == "failure")
  defp apply_status_filter(query, "success"), do: where(query, [tcr], tcr.status == "success")
  defp apply_status_filter(query, "skipped"), do: where(query, [tcr], tcr.status == "skipped")
  defp apply_status_filter(query, "flaky"), do: where(query, [tcr], tcr.is_flaky == true)

  @doc """
  Gets test case run duration analytics for a project over a time period.
  Returns average duration with percentiles (p50, p90, p99) and trend data for charts.

  ## Options
    * `:start_date` - Start date for the analytics period (default: 30 days ago)
    * `:end_date` - End date for the analytics period (default: today)
    * `:is_ci` - Filter by CI runs (true/false/nil for all)
  """
  def test_case_run_duration_analytics(project_id, opts \\ []) do
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())

    days_delta = Date.diff(DateTime.to_date(end_datetime), DateTime.to_date(start_datetime))
    date_period = date_period(start_datetime: start_datetime, end_datetime: end_datetime)
    time_bucket = time_bucket_for_date_period(date_period)
    clickhouse_time_bucket = time_bucket_to_clickhouse_interval(time_bucket)

    previous_period_total_average_duration =
      test_case_run_aggregated_duration(project_id, DateTime.add(start_datetime, -days_delta, :day), start_datetime, opts)

    current_period_total_average_duration =
      test_case_run_aggregated_duration(project_id, start_datetime, end_datetime, opts)

    current_period_percentiles =
      test_case_run_duration_percentiles(project_id, start_datetime, end_datetime, opts)

    average_durations_data =
      test_case_run_average_durations(
        project_id,
        start_datetime,
        end_datetime,
        date_period,
        clickhouse_time_bucket,
        opts
      )

    percentile_durations_data =
      test_case_run_percentile_durations(
        project_id,
        start_datetime,
        end_datetime,
        date_period,
        clickhouse_time_bucket,
        opts
      )

    average_durations =
      process_durations_data(average_durations_data, start_datetime, end_datetime, date_period)

    p50_durations =
      process_durations_data(
        Enum.map(percentile_durations_data, fn row -> %{date: row.date, value: row.p50} end),
        start_datetime,
        end_datetime,
        date_period
      )

    p90_durations =
      process_durations_data(
        Enum.map(percentile_durations_data, fn row -> %{date: row.date, value: row.p90} end),
        start_datetime,
        end_datetime,
        date_period
      )

    p99_durations =
      process_durations_data(
        Enum.map(percentile_durations_data, fn row -> %{date: row.date, value: row.p99} end),
        start_datetime,
        end_datetime,
        date_period
      )

    %{
      trend:
        trend(
          previous_value: previous_period_total_average_duration,
          current_value: current_period_total_average_duration
        ),
      total_average_duration: current_period_total_average_duration,
      p50: current_period_percentiles.p50,
      p90: current_period_percentiles.p90,
      p99: current_period_percentiles.p99,
      average_durations: average_durations,
      dates: Enum.map(average_durations, & &1.date),
      values: Enum.map(average_durations, & &1.value),
      p50_values: Enum.map(p50_durations, & &1.value),
      p90_values: Enum.map(p90_durations, & &1.value),
      p99_values: Enum.map(p99_durations, & &1.value)
    }
  end

  defp test_case_run_aggregated_duration(project_id, start_datetime, end_datetime, opts) do
    is_ci = Keyword.get(opts, :is_ci)

    query =
      from(tcr in TestCaseRun,
        where: tcr.project_id == ^project_id,
        where: tcr.inserted_at >= ^start_datetime,
        where: tcr.inserted_at <= ^end_datetime,
        select: avg(tcr.duration)
      )

    query =
      case is_ci do
        nil -> query
        true -> where(query, [tcr], tcr.is_ci == true)
        false -> where(query, [tcr], tcr.is_ci == false)
      end

    result = ClickHouseRepo.one(query)

    case result do
      nil -> 0.0
      avg when is_float(avg) -> avg
      avg -> avg * 1.0
    end
  end

  defp test_case_run_duration_percentiles(project_id, start_datetime, end_datetime, opts) do
    is_ci = Keyword.get(opts, :is_ci)

    query =
      from(tcr in TestCaseRun,
        where: tcr.project_id == ^project_id,
        where: tcr.inserted_at >= ^start_datetime,
        where: tcr.inserted_at <= ^end_datetime,
        select: %{
          p50: fragment("quantile(0.50)(?)", tcr.duration),
          p90: fragment("quantile(0.90)(?)", tcr.duration),
          p99: fragment("quantile(0.99)(?)", tcr.duration)
        }
      )

    query =
      case is_ci do
        nil -> query
        true -> where(query, [tcr], tcr.is_ci == true)
        false -> where(query, [tcr], tcr.is_ci == false)
      end

    result = ClickHouseRepo.one(query)

    case result do
      %{p50: p50, p90: p90, p99: p99} ->
        %{
          p50: normalize_percentile(p50),
          p90: normalize_percentile(p90),
          p99: normalize_percentile(p99)
        }

      _ ->
        %{p50: 0.0, p90: 0.0, p99: 0.0}
    end
  end

  defp normalize_percentile(nil), do: 0.0
  defp normalize_percentile(value) when is_float(value), do: value
  defp normalize_percentile(value), do: value * 1.0

  defp test_case_run_average_durations(project_id, start_datetime, end_datetime, _date_period, time_bucket, opts) do
    date_format = get_clickhouse_date_format(time_bucket)

    is_ci = Keyword.get(opts, :is_ci)

    query =
      from(tcr in TestCaseRun,
        where: tcr.project_id == ^project_id,
        where: tcr.inserted_at >= ^start_datetime,
        where: tcr.inserted_at <= ^end_datetime,
        group_by: fragment("formatDateTime(?, ?)", tcr.inserted_at, ^date_format),
        select: %{
          date: fragment("formatDateTime(?, ?)", tcr.inserted_at, ^date_format),
          value: avg(tcr.duration)
        },
        order_by: fragment("formatDateTime(?, ?)", tcr.inserted_at, ^date_format)
      )

    query =
      case is_ci do
        nil -> query
        true -> where(query, [tcr], tcr.is_ci == true)
        false -> where(query, [tcr], tcr.is_ci == false)
      end

    ClickHouseRepo.all(query)
  end

  defp test_case_run_percentile_durations(project_id, start_datetime, end_datetime, _date_period, time_bucket, opts) do
    date_format = get_clickhouse_date_format(time_bucket)

    is_ci = Keyword.get(opts, :is_ci)

    query =
      from(tcr in TestCaseRun,
        where: tcr.project_id == ^project_id,
        where: tcr.inserted_at >= ^start_datetime,
        where: tcr.inserted_at <= ^end_datetime,
        group_by: fragment("formatDateTime(?, ?)", tcr.inserted_at, ^date_format),
        select: %{
          date: fragment("formatDateTime(?, ?)", tcr.inserted_at, ^date_format),
          p50: fragment("quantile(0.5)(?)", tcr.duration),
          p90: fragment("quantile(0.9)(?)", tcr.duration),
          p99: fragment("quantile(0.99)(?)", tcr.duration)
        },
        order_by: fragment("formatDateTime(?, ?)", tcr.inserted_at, ^date_format)
      )

    query =
      case is_ci do
        nil -> query
        true -> where(query, [tcr], tcr.is_ci == true)
        false -> where(query, [tcr], tcr.is_ci == false)
      end

    query
    |> ClickHouseRepo.all()
    |> Enum.map(fn row ->
      %{
        date: row.date,
        p50: row.p50 || 0,
        p90: row.p90 || 0,
        p99: row.p99 || 0
      }
    end)
  end

  @doc """
  Calculates the test reliability (success rate) for a specific test case by its UUID.
  First attempts to calculate based on the project's default branch. If no runs exist on the
  default branch, falls back to calculating reliability across all branches.
  Returns the percentage of successful runs (0-100) or nil if no runs exist at all.
  """
  def test_case_reliability_by_id(test_case_id, default_branch) do
    default_branch_query =
      from(tcr in TestCaseRun,
        where: tcr.test_case_id == ^test_case_id,
        where: tcr.git_branch == ^default_branch,
        select: %{
          success_count: fragment("countIf(? = 'success')", tcr.status),
          total_count: count(tcr.id)
        }
      )

    result = ClickHouseRepo.one(default_branch_query)

    case result do
      %{success_count: success_count, total_count: total_count} when total_count > 0 ->
        Float.round(success_count / total_count * 100, 1)

      _ ->
        all_branches_query =
          from(tcr in TestCaseRun,
            where: tcr.test_case_id == ^test_case_id,
            select: %{
              success_count: fragment("countIf(? = 'success')", tcr.status),
              total_count: count(tcr.id)
            }
          )

        all_result = ClickHouseRepo.one(all_branches_query)

        case all_result do
          %{success_count: success_count, total_count: total_count} when total_count > 0 ->
            Float.round(success_count / total_count * 100, 1)

          _ ->
            nil
        end
    end
  end

  @doc """
  Gets analytics for a specific test case by its UUID including total runs, failed runs, and average duration.
  """
  def test_case_analytics_by_id(test_case_id, _opts \\ []) do
    query =
      from(tcr in TestCaseRun,
        where: tcr.test_case_id == ^test_case_id,
        select: %{
          total_count: count(tcr.id),
          failed_count: fragment("countIf(? = 'failure')", tcr.status),
          avg_duration: avg(tcr.duration)
        }
      )

    result = ClickHouseRepo.one(query)

    case result do
      nil ->
        %{total_count: 0, failed_count: 0, avg_duration: 0}

      %{total_count: total, failed_count: failed, avg_duration: avg} ->
        %{
          total_count: total,
          failed_count: failed,
          avg_duration: normalize_duration(avg)
        }
    end
  end

  @doc """
  Gets the flakiness rate for a specific test case.
  Calculates the ratio of flaky runs to total runs in the last 30 days.
  Returns 0.0 if there are no flaky runs or no data.
  """
  def get_test_case_flakiness_rate(%TestCase{id: test_case_id}) do
    thirty_days_ago = DateTime.add(DateTime.utc_now(), -30, :day)

    query =
      from(tcr in TestCaseRun,
        where: tcr.test_case_id == ^test_case_id,
        where: tcr.inserted_at >= ^thirty_days_ago,
        select: %{
          flaky_count: fragment("countIf(?)", tcr.is_flaky),
          total_count: count(tcr.id)
        }
      )

    result = ClickHouseRepo.one(query)

    case result do
      %{flaky_count: flaky_count, total_count: total_count} when total_count > 0 ->
        Float.round(flaky_count / total_count * 100, 1)

      _ ->
        0.0
    end
  end

  defp normalize_duration(nil), do: 0
  defp normalize_duration(value) when is_float(value), do: round(value)
  defp normalize_duration(value) when is_integer(value), do: value
  defp normalize_duration(value), do: round(value * 1.0)

  @doc """
  Gets a single test duration metric for the last N tests.

  ## Parameters
    * `project_id` - The project ID
    * `metric` - The metric to calculate: `:p50`, `:p90`, `:p99`, or `:average`
    * `opts` - Options:
      * `:limit` - Number of tests to consider (default: 100)
      * `:offset` - Number of tests to skip (default: 0)

  ## Returns
    The calculated metric value, or `nil` if no data available.
  """
  def test_duration_metric_by_count(project_id, metric, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    durations =
      ClickHouseRepo.all(
        from(t in Test,
          where: t.project_id == ^project_id,
          order_by: [desc: t.ran_at],
          limit: ^limit,
          offset: ^offset,
          select: t.duration
        )
      )

    calculate_metric_from_values(durations, metric)
  end

  defp calculate_metric_from_values([], _metric), do: nil

  defp calculate_metric_from_values(values, :average) do
    Enum.sum(values) / length(values)
  end

  defp calculate_metric_from_values(values, percentile) do
    sorted = Enum.sort(values)
    count = length(sorted)

    index =
      case percentile do
        :p50 -> trunc(count * 0.5)
        :p90 -> trunc(count * 0.9)
        :p99 -> trunc(count * 0.99)
      end

    index = min(index, count - 1)
    Enum.at(sorted, index)
  end

  # Shared helper functions

  @doc """
  Returns the trend between the current value and the previous value as a percentage value. The value is negative if the current_value is smaller than previous_value.

  Returns 0 if the previous value is 0 or if the current value is 0.
  """
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
        Float.round(
          current_value / previous_value * 100,
          1
        ) - 100.0
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

  defp time_bucket_for_date_period(date_period) do
    case date_period do
      :hour -> %Interval{secs: 3600}
      :day -> %Interval{days: 1}
      :month -> %Interval{months: 1}
    end
  end

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

  defp get_clickhouse_date_format("1 hour"), do: "%Y-%m-%d %H:00"
  defp get_clickhouse_date_format("1 day"), do: "%Y-%m-%d"
  defp get_clickhouse_date_format("1 month"), do: "%Y-%m"
  defp get_clickhouse_date_format(_), do: "%Y-%m-%d"
end
