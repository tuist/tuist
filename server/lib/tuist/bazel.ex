defmodule Tuist.Bazel do
  @moduledoc false

  import Ecto.Query

  alias Tuist.Bazel.Invocation
  alias Tuist.Bazel.InvocationLog
  alias Tuist.Bazel.TestResult
  alias Tuist.ClickHouseFlop
  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.ReapiCache

  def create_invocations([]), do: {:ok, 0}

  def create_invocations(invocations) when is_list(invocations) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    entries =
      Enum.map(invocations, fn invocation ->
        %{
          id: UUIDv7.generate(),
          invocation_id: invocation.invocation_id,
          command: invocation.command,
          status: invocation.status,
          exit_code: invocation.exit_code,
          started_at: invocation.started_at,
          finished_at: invocation.finished_at,
          duration_ms: invocation.duration_ms,
          target_patterns: Map.get(invocation, :target_patterns, []),
          requested_command: Map.get(invocation, :requested_command, ""),
          original_command_line: Map.get(invocation, :original_command_line, []),
          canonical_command_line: Map.get(invocation, :canonical_command_line, []),
          bazel_version: Map.get(invocation, :bazel_version, ""),
          client_platform: Map.get(invocation, :client_platform, "unknown"),
          git_branch: Map.get(invocation, :git_branch, ""),
          git_commit_sha: Map.get(invocation, :git_commit_sha, ""),
          configurations: Map.get(invocation, :configurations, []),
          compilation_mode: Map.get(invocation, :compilation_mode, ""),
          remote_cache_enabled: Map.get(invocation, :remote_cache_enabled, false),
          remote_execution_enabled: Map.get(invocation, :remote_execution_enabled, false),
          cpu_time_ms: Map.get(invocation, :cpu_time_ms, 0),
          actions_executed: Map.get(invocation, :actions_executed, 0),
          targets_loaded: Map.get(invocation, :targets_loaded, 0),
          targets_configured: Map.get(invocation, :targets_configured, 0),
          packages_loaded: Map.get(invocation, :packages_loaded, 0),
          build_timeline_duration_ms: Map.get(invocation, :build_timeline_duration_ms, 0),
          build_timeline_lanes: Map.get(invocation, :build_timeline_lanes, []),
          build_timeline_span_lanes: Map.get(invocation, :build_timeline_span_lanes, []),
          build_timeline_span_start_ms: Map.get(invocation, :build_timeline_span_start_ms, []),
          build_timeline_span_durations_ms: Map.get(invocation, :build_timeline_span_durations_ms, []),
          build_timeline_span_categories: Map.get(invocation, :build_timeline_span_categories, []),
          build_timeline_span_descriptions: Map.get(invocation, :build_timeline_span_descriptions, []),
          critical_path_duration_ms: Map.get(invocation, :critical_path_duration_ms, 0),
          critical_path_action_descriptions: Map.get(invocation, :critical_path_action_descriptions, []),
          critical_path_action_durations_ms: Map.get(invocation, :critical_path_action_durations_ms, []),
          project_id: invocation.project_id,
          account_handle: invocation.account_handle,
          project_handle: invocation.project_handle,
          cache_endpoint: invocation.cache_endpoint,
          inserted_at: now
        }
      end)

    IngestRepo.insert_all(Invocation, entries)
  end

  def create_test_results([]), do: {:ok, 0}

  def create_test_results(test_results) when is_list(test_results) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    entries =
      Enum.map(test_results, fn test_result ->
        %{
          id: UUIDv7.generate(),
          invocation_id: test_result.invocation_id,
          target_label: test_result.target_label,
          status: test_result.status,
          duration_ms: test_result.duration_ms,
          attempt_count: test_result.attempt_count,
          finished_at: test_result.finished_at,
          project_id: test_result.project_id,
          account_handle: test_result.account_handle,
          project_handle: test_result.project_handle,
          cache_endpoint: test_result.cache_endpoint,
          inserted_at: now
        }
      end)

    IngestRepo.insert_all(TestResult, entries)
  end

  def create_invocation_logs([]), do: {:ok, 0}

  def create_invocation_logs(logs) when is_list(logs) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    entries =
      Enum.map(logs, fn log ->
        %{
          id: UUIDv7.generate(),
          invocation_id: log.invocation_id,
          sequence_number: log.sequence_number,
          stream: log.stream,
          message: log.message,
          project_id: log.project_id,
          observed_at: log.observed_at,
          inserted_at: now
        }
      end)

    IngestRepo.insert_all(InvocationLog, entries)
  end

  def invocation_logs_present?(project_id, invocation_id) do
    ClickHouseRepo.exists?(
      from(log in InvocationLog,
        where: log.project_id == ^project_id and log.invocation_id == ^invocation_id
      )
    )
  end

  def invocation_logs(project_id, invocation_id) do
    ClickHouseRepo.all(
      from(log in InvocationLog,
        where: log.project_id == ^project_id and log.invocation_id == ^invocation_id,
        order_by: [asc: log.sequence_number]
      )
    )
  end

  def recent_invocation_logs(project_id, invocation_id, limit \\ 200) do
    project_id
    |> invocation_logs_query(invocation_id)
    |> order_by([log], desc: log.sequence_number)
    |> limit(^limit)
    |> ClickHouseRepo.all()
    |> Enum.reverse()
  end

  def list_invocations(project_id, flop_params \\ %{}) do
    {commands, flop_params} = Map.pop(flop_params, :commands, nil)

    {invocations, meta} =
      Invocation
      |> where([invocation], invocation.project_id == ^project_id)
      |> maybe_filter_commands(commands)
      |> ClickHouseFlop.validate_and_run!(flop_params, for: Invocation)

    with_cache_summaries(project_id, invocations, meta)
  end

  def get_invocation(project_id, invocation_id) do
    invocation =
      ClickHouseRepo.one(
        from(invocation in Invocation,
          where: invocation.project_id == ^project_id and invocation.invocation_id == ^invocation_id,
          order_by: [desc: invocation.inserted_at],
          limit: 1
        )
      )

    case invocation do
      nil -> {:error, :not_found}
      invocation -> {:ok, Map.put(invocation, :cache, ReapiCache.invocation_summary(project_id, invocation_id))}
    end
  end

  def list_test_results(project_id, flop_params \\ %{}) do
    TestResult
    |> where([test_result], test_result.project_id == ^project_id)
    |> ClickHouseFlop.validate_and_run!(flop_params, for: TestResult)
  end

  def get_test_result(project_id, test_result_id) do
    case ClickHouseRepo.one(
           from(test_result in TestResult,
             where: test_result.project_id == ^project_id and test_result.id == ^test_result_id,
             order_by: [desc: test_result.inserted_at],
             limit: 1
           )
         ) do
      nil -> {:error, :not_found}
      test_result -> {:ok, test_result}
    end
  end

  def test_summary(project_id, opts \\ []) do
    query = test_result_query(project_id, opts)

    result =
      ClickHouseRepo.one(
        from(test_result in query,
          select: %{
            total: count(test_result.id),
            successful:
              coalesce(
                sum(fragment("if(? IN ('success', 'flaky'), 1, 0)", test_result.status)),
                0
              ),
            failed: coalesce(sum(fragment("if(? = 'failure', 1, 0)", test_result.status)), 0),
            average_duration_ms: coalesce(avg(test_result.duration_ms), 0),
            median_duration_ms: fragment("quantile(0.5)(?)", test_result.duration_ms),
            p90_duration_ms: fragment("quantile(0.9)(?)", test_result.duration_ms),
            p99_duration_ms: fragment("quantile(0.99)(?)", test_result.duration_ms)
          }
        )
      )

    result ||
      %{
        total: 0,
        successful: 0,
        failed: 0,
        average_duration_ms: 0,
        median_duration_ms: 0,
        p90_duration_ms: 0,
        p99_duration_ms: 0
      }
  end

  def test_analytics(project_id, opts \\ []) do
    project_id
    |> test_result_query(opts)
    |> daily_analytics(opts, ["success", "flaky"])
  end

  def summary(project_id, opts \\ []) do
    query = invocation_query(project_id, opts)

    result =
      ClickHouseRepo.one(
        from(invocation in query,
          select: %{
            total: count(invocation.id),
            successful: coalesce(sum(fragment("if(? = 'success', 1, 0)", invocation.status)), 0),
            failed: coalesce(sum(fragment("if(? = 'failure', 1, 0)", invocation.status)), 0),
            average_duration_ms: coalesce(avg(invocation.duration_ms), 0),
            median_duration_ms: fragment("quantile(0.5)(?)", invocation.duration_ms),
            p90_duration_ms: fragment("quantile(0.9)(?)", invocation.duration_ms),
            p99_duration_ms: fragment("quantile(0.99)(?)", invocation.duration_ms)
          }
        )
      )

    result ||
      %{
        total: 0,
        successful: 0,
        failed: 0,
        average_duration_ms: 0,
        median_duration_ms: 0,
        p90_duration_ms: 0,
        p99_duration_ms: 0
      }
  end

  def invocation_analytics(project_id, opts \\ []) do
    project_id
    |> invocation_query(opts)
    |> daily_analytics(opts, ["success"])
  end

  def duration_analytics(project_id, opts \\ []) do
    analytics = invocation_analytics(project_id, opts)

    %{
      dates: analytics.dates,
      values: analytics.average_duration_values,
      total_average_duration: summary(project_id, opts).average_duration_ms
    }
  end

  def recent_invocations(project_id, limit \\ 30)

  def recent_invocations(project_id, limit) when is_integer(limit) do
    recent_invocations(project_id, limit: limit)
  end

  def recent_invocations(project_id, opts) when is_list(opts) do
    limit = Keyword.get(opts, :limit, 30)

    invocations =
      project_id
      |> invocation_query(opts)
      |> order_by([invocation], desc: invocation.finished_at)
      |> limit(^limit)
      |> ClickHouseRepo.all()

    {invocations, _meta} = with_cache_summaries(project_id, invocations, %{})
    invocations
  end

  defp with_cache_summaries(_project_id, [], meta), do: {[], meta}

  defp with_cache_summaries(project_id, invocations, meta) do
    invocation_ids = Enum.map(invocations, & &1.invocation_id)
    summaries = ReapiCache.invocation_summaries(project_id, invocation_ids)

    invocations =
      Enum.map(invocations, fn invocation ->
        Map.put(invocation, :cache, Map.get(summaries, invocation.invocation_id, ReapiCache.empty_summary()))
      end)

    {invocations, meta}
  end

  defp invocation_query(project_id, opts) do
    query =
      maybe_filter_commands(
        from(invocation in Invocation, where: invocation.project_id == ^project_id),
        Keyword.get(opts, :commands)
      )

    case_result =
      case Keyword.get(opts, :start_datetime) do
        nil ->
          query

        start_datetime ->
          where(
            query,
            [invocation],
            invocation.finished_at >= fragment("toDateTime(?, 'UTC')", ^datetime_string(start_datetime))
          )
      end

    then(case_result, fn query ->
      case Keyword.get(opts, :end_datetime) do
        nil ->
          query

        end_datetime ->
          where(
            query,
            [invocation],
            invocation.finished_at < fragment("toDateTime(?, 'UTC')", ^datetime_string(end_datetime))
          )
      end
    end)
  end

  defp invocation_logs_query(project_id, invocation_id) do
    from(log in InvocationLog,
      where: log.project_id == ^project_id and log.invocation_id == ^invocation_id
    )
  end

  defp test_result_query(project_id, opts) do
    query = from(test_result in TestResult, where: test_result.project_id == ^project_id)

    query =
      case Keyword.get(opts, :start_datetime) do
        nil ->
          query

        start_datetime ->
          where(
            query,
            [test_result],
            test_result.finished_at >= fragment("toDateTime(?, 'UTC')", ^datetime_string(start_datetime))
          )
      end

    case Keyword.get(opts, :end_datetime) do
      nil ->
        query

      end_datetime ->
        where(
          query,
          [test_result],
          test_result.finished_at < fragment("toDateTime(?, 'UTC')", ^datetime_string(end_datetime))
        )
    end
  end

  defp daily_analytics(query, opts, successful_statuses) do
    %{start_datetime: start_datetime, end_datetime: end_datetime} = period(opts)

    values_by_date =
      from(record in query,
        group_by: fragment("toDate(?)", record.finished_at),
        order_by: fragment("toDate(?)", record.finished_at),
        select: %{
          date: fragment("toDate(?)", record.finished_at),
          total: count(record.id),
          successful: coalesce(sum(fragment("if(? IN ?, 1, 0)", record.status, ^successful_statuses)), 0),
          failed: coalesce(sum(fragment("if(? = 'failure', 1, 0)", record.status)), 0),
          average_duration_ms: coalesce(avg(record.duration_ms), 0),
          median_duration_ms: fragment("quantile(0.5)(?)", record.duration_ms),
          p90_duration_ms: fragment("quantile(0.9)(?)", record.duration_ms),
          p99_duration_ms: fragment("quantile(0.99)(?)", record.duration_ms)
        }
      )
      |> ClickHouseRepo.all()
      |> Map.new(fn result -> {result.date, result} end)

    dates = start_datetime |> DateTime.to_date() |> Date.range(DateTime.to_date(end_datetime)) |> Enum.to_list()

    %{
      dates: dates,
      total_values: Enum.map(dates, &daily_value(values_by_date, &1, :total)),
      success_rate_values: Enum.map(dates, &daily_success_rate(values_by_date, &1)),
      failed_values: Enum.map(dates, &daily_value(values_by_date, &1, :failed)),
      average_duration_values: Enum.map(dates, &daily_value(values_by_date, &1, :average_duration_ms)),
      median_duration_values: Enum.map(dates, &daily_value(values_by_date, &1, :median_duration_ms)),
      p90_duration_values: Enum.map(dates, &daily_value(values_by_date, &1, :p90_duration_ms)),
      p99_duration_values: Enum.map(dates, &daily_value(values_by_date, &1, :p99_duration_ms))
    }
  end

  defp daily_success_rate(values_by_date, date) do
    case Map.get(values_by_date, date) do
      %{total: total, successful: successful} when total > 0 -> successful / total * 100
      _ -> 0
    end
  end

  defp daily_value(values_by_date, date, key) do
    values_by_date
    |> Map.get(date, %{})
    |> Map.get(key, 0)
  end

  defp period(opts) do
    %{
      start_datetime: Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day)),
      end_datetime: Keyword.get(opts, :end_datetime, DateTime.utc_now())
    }
  end

  defp datetime_string(datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_naive()
    |> NaiveDateTime.to_string()
  end

  defp maybe_filter_commands(query, commands) when is_list(commands) and commands != [] do
    where(query, [invocation], invocation.command in ^commands)
  end

  defp maybe_filter_commands(query, _commands), do: query
end
