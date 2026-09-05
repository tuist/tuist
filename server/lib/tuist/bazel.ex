defmodule Tuist.Bazel do
  @moduledoc false

  import Ecto.Query

  alias Tuist.Bazel.Invocation
  alias Tuist.Bazel.InvocationLog
  alias Tuist.Bazel.TestInvocation
  alias Tuist.Bazel.TestReportIngestor
  alias Tuist.Bazel.TestResult
  alias Tuist.Bazel.TestSummary
  alias Tuist.Bazel.Workers.ProcessTestInvocationWorker
  alias Tuist.ClickHouseFlop
  alias Tuist.ClickHouseRepo
  alias Tuist.ClickHouseTimeSeries
  alias Tuist.IngestRepo
  alias Tuist.ReapiCache
  alias Tuist.Repo
  alias Tuist.Tests.Sanitizer

  @max_test_artifact_bytes_per_invocation 64 * 1_024 * 1_024
  @ingest_pruning_slack_seconds 24 * 60 * 60

  def sanitize_invocation_log(message), do: Sanitizer.sanitize(message)

  def ingest_test_report(project, invocation, test_results, test_summaries) do
    TestReportIngestor.ingest(project, invocation, test_results, test_summaries)
  end

  def create_invocations([]), do: {0, nil}

  def create_invocations(invocations) when is_list(invocations) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    entries =
      Enum.map(invocations, fn invocation ->
        %{
          id: UUIDv7.generate(),
          invocation_id: invocation.invocation_id,
          command: invocation.command,
          target_patterns: Map.get(invocation, :target_patterns, []),
          git_branch: Map.get(invocation, :git_branch, ""),
          git_commit_sha: Map.get(invocation, :git_commit_sha, ""),
          is_ci: Map.get(invocation, :is_ci, false),
          bazel_version: Map.get(invocation, :bazel_version, ""),
          cpu_time_ms: Map.get(invocation, :cpu_time_ms, 0),
          actions_created: Map.get(invocation, :actions_created, 0),
          actions_executed: Map.get(invocation, :actions_executed, 0),
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
          status: invocation.status,
          exit_code: invocation.exit_code,
          started_at: invocation.started_at,
          finished_at: invocation.finished_at,
          duration_ms: invocation.duration_ms,
          project_id: invocation.project_id,
          account_handle: invocation.account_handle,
          project_handle: invocation.project_handle,
          cache_endpoint: invocation.cache_endpoint,
          inserted_at: now
        }
      end)

    IngestRepo.insert_all(Invocation, entries)
  end

  def create_invocation_logs([]), do: {0, nil}

  def create_invocation_logs(logs) when is_list(logs) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    entries =
      Enum.map(logs, fn log ->
        %{
          id: Map.get(log, :id) || UUIDv7.generate(),
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

  def invocation_logs_present?(project_id, invocation_id, opts \\ []) do
    project_id
    |> invocation_log_query(invocation_id, opts)
    |> ClickHouseRepo.exists?()
  end

  def stage_test_result(attrs, max_artifact_bytes \\ @max_test_artifact_bytes_per_invocation) when is_map(attrs) do
    result =
      Repo.transaction(fn ->
        test_invocation = lock_test_invocation(attrs.project_id, attrs.invocation_id)

        if test_invocation.state == "processed" do
          :already_processed
        else
          previous_bytes = test_result_artifact_bytes(attrs)
          next_bytes = test_invocation.artifact_bytes - previous_bytes + artifact_bytes(attrs)

          if next_bytes > max_artifact_bytes do
            Repo.rollback(:artifact_limit_exceeded)
          end

          upsert_test_result(attrs)

          test_invocation
          |> Ecto.Changeset.change(%{artifact_bytes: next_bytes})
          |> Repo.update!()

          :staged
        end
      end)

    case result do
      {:ok, _state} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def stage_test_summary(attrs) when is_map(attrs) do
    {:ok, _state} =
      Repo.transaction(fn ->
        test_invocation = lock_test_invocation(attrs.project_id, attrs.invocation_id)

        if test_invocation.state == "processed" do
          :already_processed
        else
          upsert_test_summary(attrs)
          :staged
        end
      end)

    :ok
  end

  defp upsert_test_result(attrs) when is_map(attrs) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    entry =
      attrs
      |> Map.take([
        :project_id,
        :invocation_id,
        :target_label,
        :run,
        :shard,
        :attempt,
        :status,
        :duration_ms,
        :started_at,
        :cached,
        :is_ci,
        :sequence_number,
        :junit_digest,
        :junit_content,
        :log_digest,
        :log_content
      ])
      |> Map.merge(%{id: UUIDv7.generate(), inserted_at: now, updated_at: now})

    Repo.insert_all(
      TestResult,
      [entry],
      on_conflict:
        {:replace,
         [
           :status,
           :duration_ms,
           :started_at,
           :cached,
           :is_ci,
           :sequence_number,
           :junit_digest,
           :junit_content,
           :log_digest,
           :log_content,
           :updated_at
         ]},
      conflict_target: [:project_id, :invocation_id, :target_label, :run, :shard, :attempt]
    )

    :ok
  end

  defp upsert_test_summary(attrs) when is_map(attrs) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    entry =
      attrs
      |> Map.take([
        :project_id,
        :invocation_id,
        :target_label,
        :status,
        :total_run_count,
        :total_num_cached,
        :duration_ms,
        :started_at,
        :finished_at
      ])
      |> Map.merge(%{id: UUIDv7.generate(), inserted_at: now, updated_at: now})

    Repo.insert_all(
      TestSummary,
      [entry],
      on_conflict:
        {:replace,
         [
           :status,
           :total_run_count,
           :total_num_cached,
           :duration_ms,
           :started_at,
           :finished_at,
           :updated_at
         ]},
      conflict_target: [:project_id, :invocation_id, :target_label]
    )

    :ok
  end

  def record_test_invocation_event(project_id, invocation_id) do
    ensure_test_invocation(project_id, invocation_id)
    :ok
  end

  def complete_test_invocation(project_id, invocation_id) do
    Repo.transaction(fn ->
      test_invocation = lock_test_invocation(project_id, invocation_id)

      if test_invocation.state == "processed" do
        :already_processed
      else
        test_invocation
        |> Ecto.Changeset.change(%{state: "pending"})
        |> Repo.update!()

        %{"project_id" => project_id, "invocation_id" => invocation_id}
        |> ProcessTestInvocationWorker.new()
        |> Oban.insert!()
      end
    end)
  end

  def get_test_invocation(project_id, invocation_id) do
    Repo.one(
      from(test_invocation in TestInvocation,
        where: test_invocation.project_id == ^project_id and test_invocation.invocation_id == ^invocation_id
      )
    )
  end

  def list_test_results(project_id, invocation_id) do
    Repo.all(
      from(test_result in TestResult,
        where: test_result.project_id == ^project_id and test_result.invocation_id == ^invocation_id,
        order_by: [asc: test_result.sequence_number, asc: test_result.target_label]
      )
    )
  end

  def list_test_summaries(project_id, invocation_id) do
    Repo.all(
      from(test_summary in TestSummary,
        where: test_summary.project_id == ^project_id and test_summary.invocation_id == ^invocation_id,
        order_by: [asc: test_summary.target_label]
      )
    )
  end

  def mark_test_invocation_processed(test_invocation) do
    test_invocation
    |> Ecto.Changeset.change(%{state: "processed", artifact_bytes: 0})
    |> Repo.update()
  end

  def discard_test_invocation(test_invocation) do
    Repo.transaction(fn ->
      locked_invocation = lock_test_invocation(test_invocation.project_id, test_invocation.invocation_id)

      delete_test_results(locked_invocation.project_id, locked_invocation.invocation_id)
      delete_test_summaries(locked_invocation.project_id, locked_invocation.invocation_id)

      locked_invocation
      |> Ecto.Changeset.change(%{state: "processed", artifact_bytes: 0})
      |> Repo.update!()
    end)
  end

  def delete_test_results(project_id, invocation_id) do
    Repo.delete_all(
      from(test_result in TestResult,
        where: test_result.project_id == ^project_id and test_result.invocation_id == ^invocation_id
      )
    )
  end

  def delete_test_summaries(project_id, invocation_id) do
    Repo.delete_all(
      from(test_summary in TestSummary,
        where: test_summary.project_id == ^project_id and test_summary.invocation_id == ^invocation_id
      )
    )
  end

  def delete_expired_test_ingestion_records(before, batch_size) do
    delete_expired_batch(TestResult, before, batch_size) +
      delete_expired_batch(TestSummary, before, batch_size) +
      delete_expired_test_invocations(before, batch_size)
  end

  defp ensure_test_invocation(project_id, invocation_id) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    Repo.insert_all(
      TestInvocation,
      [
        %{
          id: UUIDv7.generate(),
          project_id: project_id,
          invocation_id: invocation_id,
          state: "collecting",
          test_run_id: UUIDv7.generate(),
          artifact_bytes: 0,
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: {:replace, [:updated_at]},
      conflict_target: [:project_id, :invocation_id]
    )
  end

  defp lock_test_invocation(project_id, invocation_id) do
    ensure_test_invocation(project_id, invocation_id)

    Repo.one!(
      from(test_invocation in TestInvocation,
        where: test_invocation.project_id == ^project_id and test_invocation.invocation_id == ^invocation_id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp test_result_artifact_bytes(attrs) do
    Repo.one(
      from(test_result in TestResult,
        where:
          test_result.project_id == ^attrs.project_id and test_result.invocation_id == ^attrs.invocation_id and
            test_result.target_label == ^attrs.target_label and test_result.run == ^attrs.run and
            test_result.shard == ^attrs.shard and test_result.attempt == ^attrs.attempt,
        select:
          fragment(
            "coalesce(octet_length(?), 0) + coalesce(octet_length(?), 0)",
            test_result.junit_content,
            test_result.log_content
          )
      )
    ) || 0
  end

  defp artifact_bytes(attrs) do
    byte_size(Map.get(attrs, :junit_content) || "") + byte_size(Map.get(attrs, :log_content) || "")
  end

  defp delete_expired_batch(schema, before, batch_size) do
    ids =
      from(record in schema,
        where: record.inserted_at < ^before,
        order_by: [asc: record.inserted_at, asc: record.id],
        limit: ^batch_size,
        select: record.id
      )

    {count, _} = Repo.delete_all(from(record in schema, where: record.id in subquery(ids)))
    count
  end

  defp delete_expired_test_invocations(before, batch_size) do
    ids =
      from(invocation in TestInvocation,
        as: :invocation,
        where: invocation.inserted_at < ^before,
        where:
          not exists(
            from(result in TestResult,
              where:
                result.project_id == parent_as(:invocation).project_id and
                  result.invocation_id == parent_as(:invocation).invocation_id,
              select: 1
            )
          ),
        where:
          not exists(
            from(summary in TestSummary,
              where:
                summary.project_id == parent_as(:invocation).project_id and
                  summary.invocation_id == parent_as(:invocation).invocation_id,
              select: 1
            )
          ),
        order_by: [asc: invocation.inserted_at, asc: invocation.id],
        limit: ^batch_size,
        select: invocation.id
      )

    {count, _} = Repo.delete_all(from(invocation in TestInvocation, where: invocation.id in subquery(ids)))
    count
  end

  def list_invocations(project_id, flop_params \\ %{}, opts \\ []) do
    {commands, flop_params} = Map.pop(flop_params, :commands)

    {invocations, meta} =
      project_id
      |> invocation_query(Keyword.put(opts, :commands, commands))
      |> ClickHouseFlop.validate_and_run!(flop_params, for: Invocation)

    with_cache_summaries(project_id, invocations, meta)
  end

  def get_invocation(project_id, invocation_id, opts \\ []) do
    invocation =
      ClickHouseRepo.one(
        from(invocation in Invocation,
          hints: ["FINAL"],
          where: invocation.project_id == ^project_id and invocation.invocation_id == ^invocation_id,
          order_by: [desc: invocation.inserted_at],
          limit: 1
        )
      )

    case invocation do
      nil ->
        {:error, :not_found}

      invocation ->
        if Keyword.get(opts, :include_cache_summary, true) do
          cache = ReapiCache.invocation_summary(project_id, invocation_id, cache_summary_query_options([invocation]))
          {:ok, Map.put(invocation, :cache, cache)}
        else
          {:ok, invocation}
        end
    end
  end

  def invocations_present?(project_id, commands \\ nil) do
    end_datetime = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second) |> NaiveDateTime.add(1, :second)

    project_id
    |> invocation_query(
      commands: commands,
      start_datetime: NaiveDateTime.add(end_datetime, -90, :day),
      end_datetime: end_datetime
    )
    |> ClickHouseRepo.exists?()
  end

  def list_invocation_logs(project_id, invocation_id, flop_params \\ %{}, opts \\ []) do
    ClickHouseFlop.validate_and_run!(
      invocation_log_query(project_id, invocation_id, opts),
      flop_params,
      for: InvocationLog
    )
  end

  def list_invocation_log_batch(project_id, invocation_id, after_sequence_number, limit, opts \\ []) do
    query = invocation_log_query(project_id, invocation_id, opts)

    query =
      if is_integer(after_sequence_number) do
        where(query, [log], log.sequence_number > ^after_sequence_number)
      else
        query
      end

    ClickHouseRepo.all(
      from(log in query,
        order_by: [asc: log.sequence_number],
        limit: ^limit
      )
    )
  end

  def invocation_log_query_options(invocation) do
    [
      start_datetime: shift_datetime(invocation.started_at, -@ingest_pruning_slack_seconds),
      end_datetime: shift_datetime(invocation.finished_at, @ingest_pruning_slack_seconds)
    ]
  end

  def invocation_cache_query_options(invocation) do
    cache_summary_query_options([invocation])
  end

  def get_invocation_log(project_id, invocation_id, log_id) do
    with {:ok, log_id} <- Ecto.UUID.cast(log_id),
         %InvocationLog{} = log <-
           ClickHouseRepo.one(
             from(log in InvocationLog,
               hints: ["FINAL"],
               where:
                 log.project_id == ^project_id and log.invocation_id == ^invocation_id and
                   log.id == type(^log_id, Ecto.UUID),
               limit: 1
             )
           ) do
      {:ok, log}
    else
      _ -> {:error, :not_found}
    end
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
            average_duration_ms: fragment("coalesce(avgOrNull(?), 0)", invocation.duration_ms),
            median_duration_ms: fragment("coalesce(quantileOrNull(0.5)(?), 0)", invocation.duration_ms),
            p90_duration_ms: fragment("coalesce(quantileOrNull(0.9)(?), 0)", invocation.duration_ms),
            p99_duration_ms: fragment("coalesce(quantileOrNull(0.99)(?), 0)", invocation.duration_ms)
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
    |> daily_analytics(opts)
  end

  def duration_analytics(project_id, opts \\ []) do
    analytics = invocation_analytics(project_id, opts)

    %{
      dates: analytics.dates,
      values: analytics.average_duration_values,
      total_average_duration: divide(analytics.total_duration_ms, analytics.total)
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
    summaries = ReapiCache.invocation_summaries(project_id, invocation_ids, cache_summary_query_options(invocations))

    invocations =
      Enum.map(invocations, fn invocation ->
        Map.put(invocation, :cache, Map.get(summaries, invocation.invocation_id, ReapiCache.empty_summary()))
      end)

    {invocations, meta}
  end

  defp invocation_query(project_id, opts) do
    query =
      Invocation
      |> from(hints: ["FINAL"])
      |> where([invocation], invocation.project_id == ^project_id)
      |> maybe_filter_commands(Keyword.get(opts, :commands))

    query =
      case Keyword.get(opts, :start_datetime) do
        nil ->
          query

        start_datetime ->
          prune_start_datetime = shift_datetime(start_datetime, -@ingest_pruning_slack_seconds)

          where(
            query,
            [invocation],
            invocation.inserted_at >= ^prune_start_datetime and invocation.finished_at >= ^start_datetime
          )
      end

    case Keyword.get(opts, :end_datetime) do
      nil ->
        query

      end_datetime ->
        prune_end_datetime = shift_datetime(end_datetime, @ingest_pruning_slack_seconds)

        where(
          query,
          [invocation],
          invocation.inserted_at < ^prune_end_datetime and invocation.finished_at < ^end_datetime
        )
    end
  end

  defp invocation_log_query(project_id, invocation_id, opts) do
    query =
      from(log in InvocationLog,
        hints: ["FINAL"],
        where: log.project_id == ^project_id and log.invocation_id == ^invocation_id
      )

    query =
      case Keyword.get(opts, :start_datetime) do
        nil -> query
        start_datetime -> where(query, [log], log.observed_at >= ^start_datetime)
      end

    case Keyword.get(opts, :end_datetime) do
      nil -> query
      end_datetime -> where(query, [log], log.observed_at < ^end_datetime)
    end
  end

  defp daily_analytics(query, opts) do
    %{start_datetime: start_datetime, end_datetime: end_datetime} = period(opts)
    granularity = ClickHouseTimeSeries.granularity(start_datetime, end_datetime)
    date_format = ClickHouseTimeSeries.date_format(granularity)

    values =
      ClickHouseRepo.all(
        from(invocation in query,
          group_by: fragment("formatDateTime(?, ?)", invocation.finished_at, ^date_format),
          order_by: fragment("formatDateTime(?, ?)", invocation.finished_at, ^date_format),
          select: %{
            date: fragment("formatDateTime(?, ?)", invocation.finished_at, ^date_format),
            total: count(invocation.id),
            successful: coalesce(sum(fragment("if(? = 'success', 1, 0)", invocation.status)), 0),
            failed: coalesce(sum(fragment("if(? = 'failure', 1, 0)", invocation.status)), 0),
            average_duration_ms: coalesce(avg(invocation.duration_ms), 0),
            median_duration_ms: fragment("quantileOrNull(0.5)(?)", invocation.duration_ms),
            p90_duration_ms: fragment("quantileOrNull(0.9)(?)", invocation.duration_ms),
            p99_duration_ms: fragment("quantileOrNull(0.99)(?)", invocation.duration_ms)
          }
        )
      )

    values_by_date = Map.new(values, fn result -> {result.date, result} end)

    dates = ClickHouseTimeSeries.buckets(start_datetime, end_datetime, granularity)

    %{
      dates: dates,
      total: Enum.sum(Enum.map(values, & &1.total)),
      total_duration_ms: Enum.sum(Enum.map(values, &(numeric(&1.average_duration_ms) * &1.total))),
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

  defp maybe_filter_commands(query, commands) when is_list(commands) and commands != [] do
    where(query, [invocation], invocation.command in ^commands)
  end

  defp maybe_filter_commands(query, _commands), do: query

  defp cache_summary_query_options(invocations) do
    first_started_at = invocations |> Enum.min_by(& &1.started_at, NaiveDateTime) |> Map.fetch!(:started_at)
    last_inserted_at = invocations |> Enum.max_by(& &1.inserted_at, NaiveDateTime) |> Map.fetch!(:inserted_at)

    [
      start_datetime: shift_datetime(first_started_at, -@ingest_pruning_slack_seconds),
      end_datetime: shift_datetime(last_inserted_at, @ingest_pruning_slack_seconds)
    ]
  end

  defp shift_datetime(%DateTime{} = datetime, seconds), do: DateTime.add(datetime, seconds, :second)
  defp shift_datetime(%NaiveDateTime{} = datetime, seconds), do: NaiveDateTime.add(datetime, seconds, :second)
  defp divide(_numerator, denominator) when denominator in [nil, 0], do: 0
  defp divide(numerator, denominator), do: numeric(numerator) / numeric(denominator)
  defp numeric(%Decimal{} = value), do: Decimal.to_float(value)
  defp numeric(value) when is_number(value), do: value
  defp numeric(nil), do: 0
end
