defmodule Tuist.RemoteExecution.Analytics do
  @moduledoc "Project-scoped diagnostics from published Bazel profiles, not a usage ledger."

  import Ecto.Query

  alias Tuist.Bazel.Invocation
  alias Tuist.Bazel.Profile
  alias Tuist.Bazel.ProfileSteps
  alias Tuist.ClickHouseRepo
  alias Tuist.ClickHouseTimeSeries

  @query_opts [
    timeout: 25_000,
    settings: [
      max_execution_time: 20,
      max_memory_usage: 268_435_456,
      do_not_merge_across_partitions_select_final: 0,
      optimize_move_to_prewhere_if_final: 0,
      use_skip_indexes_if_final: 0
    ]
  ]
  @page_size 20
  # Bounds the OFFSET a page URL can request.
  @max_page 500
  @phases [queue: :remote_queue_ms, execution: :remote_execution_ms]
  @stats [:avg, :p50, :p90, :p99]
  @sort_fields ~w(ran-at duration actions execution execution-p50 execution-p90 status)

  def phases, do: Keyword.keys(@phases)

  @doc """
  Period totals plus avg/p50/p90/p99 per phase. A phase without measurements is
  nil, never zero; recorded zero durations are included.
  """
  def summary(project_id, opts) do
    project_id
    |> observations(opts)
    |> select(^aggregates())
    |> ClickHouseRepo.one(@query_opts)
    |> nest_phases()
  end

  @doc """
  The same aggregates per hour, day or month bucket, as the Builds analytics use.
  Buckets without invocations have zero counts and nil durations.
  """
  def time_series(project_id, opts) do
    {start_datetime, end_datetime} = bucket_period(opts)
    granularity = ClickHouseTimeSeries.granularity(start_datetime, end_datetime)
    date_format = ClickHouseTimeSeries.date_format(granularity)
    bucket = dynamic([_s, _p, i], fragment("formatDateTime(?, ?)", i.finished_at, ^date_format))

    rows =
      project_id
      |> observations(opts)
      |> group_by(^[bucket])
      |> select(^Map.put(aggregates(), :date, bucket))
      |> ClickHouseRepo.all(@query_opts)
      |> Map.new(&{&1.date, nest_phases(&1)})

    dates = ClickHouseTimeSeries.buckets(start_datetime, end_datetime, granularity)
    empty = nest_phases(%{invocations: 0, actions: 0})

    points = Enum.map(dates, &Map.get(rows, &1, empty))

    %{
      dates: dates,
      granularity: granularity,
      invocations: Enum.map(points, & &1.invocations),
      actions: Enum.map(points, & &1.actions),
      queue: Map.new(@stats, fn stat -> {stat, Enum.map(points, & &1.queue[stat])} end),
      execution: Map.new(@stats, fn stat -> {stat, Enum.map(points, & &1.execution[stat])} end)
    }
  end

  @doc """
  One row per invocation with remote phases. `:filters` takes Flop-style
  `%{field, op, value}` maps for `:status`, `:command`, `:target_patterns` and
  `:actions`; `:sort_by` is one of `@sort_fields` and defaults to `"ran-at"`.
  """
  def activity(project_id, opts) do
    page = min(Keyword.get(opts, :page, 1), @max_page)
    search = Keyword.get(opts, :search, "")
    filters = Keyword.get(opts, :filters, [])
    sort_by = if(Keyword.get(opts, :sort_by) in @sort_fields, do: Keyword.get(opts, :sort_by), else: "ran-at")
    direction = if Keyword.get(opts, :sort_order) == "asc", do: :asc, else: :desc

    query =
      from([_s, _p, i] in observations(project_id, opts),
        group_by: [i.invocation_id, i.command, i.target_patterns, i.status, i.duration_ms, i.finished_at],
        select: %{
          invocation_id: i.invocation_id,
          command: i.command,
          target_patterns: i.target_patterns,
          status: i.status,
          duration_ms: i.duration_ms,
          finished_at: i.finished_at,
          actions: count()
        }
      )

    query = select_merge(query, ^execution_stats())

    query =
      if search == "" do
        query
      else
        where(
          query,
          [_s, _p, i],
          fragment("positionCaseInsensitiveUTF8(?, ?) > 0", i.invocation_id, ^search) or
            fragment("positionCaseInsensitiveUTF8(?, ?) > 0", i.command, ^search) or
            fragment("positionCaseInsensitiveUTF8(arrayStringConcat(?, ' '), ?) > 0", i.target_patterns, ^search)
        )
      end

    query = Enum.reduce(filters, query, &filter_activity/2)

    # One extra row tells whether a next page exists without counting every
    # invocation in the period.
    rows =
      query
      |> order_by(^[{direction, sort_expression(sort_by)}, {:asc, dynamic([_s, _p, i], i.invocation_id)}])
      |> limit(@page_size + 1)
      |> offset(^((page - 1) * @page_size))
      |> ClickHouseRepo.all(@query_opts)

    %{rows: Enum.take(rows, @page_size), page: page, has_next_page?: length(rows) > @page_size and page < @max_page}
  end

  defp sort_expression("status"), do: dynamic([_s, _p, i], i.status)
  defp sort_expression("duration"), do: dynamic([_s, _p, i], i.duration_ms)
  defp sort_expression("actions"), do: dynamic(fragment("count()"))
  # Invocations without execution measurements are NULL and sort last in both directions.
  defp sort_expression("execution"), do: stat(:avg, :remote_execution_ms)

  defp sort_expression("execution-" <> stat) when stat in ~w(p50 p90),
    do: stat(String.to_existing_atom(stat), :remote_execution_ms)

  defp sort_expression(_ran_at), do: dynamic([_s, _p, i], i.finished_at)

  defp execution_stats,
    do: for(stat <- [:avg, :p50, :p90], into: %{}, do: {execution_key(stat), stat(stat, :remote_execution_ms)})

  defp execution_key(:avg), do: :execution_ms
  defp execution_key(stat), do: :"execution_#{stat}_ms"

  defp filter_activity(%{field: :status, op: op, value: value}, query) when op in [:==, :!=] do
    if op == :==, do: where(query, [_s, _p, i], i.status == ^value), else: where(query, [_s, _p, i], i.status != ^value)
  end

  defp filter_activity(%{field: :command, op: op, value: value}, query),
    do: where(query, ^text_condition(dynamic([_s, _p, i], i.command), op, value))

  defp filter_activity(%{field: :target_patterns, op: op, value: value}, query),
    do:
      where(
        query,
        ^text_condition(dynamic([_s, _p, i], fragment("arrayStringConcat(?, ' ')", i.target_patterns)), op, value)
      )

  defp filter_activity(%{field: :actions, op: op, value: value}, query) when op in [:==, :<, :>, :<=, :>=] do
    case Integer.parse(to_string(value)) do
      {count, ""} ->
        condition =
          case op do
            :== -> dynamic(fragment("count()") == ^count)
            :< -> dynamic(fragment("count()") < ^count)
            :> -> dynamic(fragment("count()") > ^count)
            :<= -> dynamic(fragment("count()") <= ^count)
            :>= -> dynamic(fragment("count()") >= ^count)
          end

        having(query, ^condition)

      _ ->
        query
    end
  end

  defp filter_activity(_filter, query), do: query

  defp text_condition(field, :==, value), do: dynamic(^field == ^value)
  defp text_condition(field, :=~, value), do: dynamic(fragment("positionCaseInsensitiveUTF8(?, ?) > 0", ^field, ^value))

  defp text_condition(field, _not_contains, value),
    do: dynamic(fragment("positionCaseInsensitiveUTF8(?, ?) = 0", ^field, ^value))

  defp aggregates do
    base = %{
      invocations: dynamic([_s, _p, i], fragment("uniqExact(?)", i.invocation_id)),
      actions: dynamic(fragment("count()"))
    }

    for {phase, field} <- @phases, stat <- @stats, into: base do
      {:"#{phase}_#{stat}", stat(stat, field)}
    end
  end

  # `count(column)` skips NULLs, so a phase without measurements stays NULL.
  defp stat(:avg, field), do: dynamic([s], fragment("if(count(?) = 0, NULL, avg(?))", field(s, ^field), field(s, ^field)))

  defp stat(:p50, field),
    do: dynamic([s], fragment("if(count(?) = 0, NULL, quantileTDigest(0.5)(?))", field(s, ^field), field(s, ^field)))

  defp stat(:p90, field),
    do: dynamic([s], fragment("if(count(?) = 0, NULL, quantileTDigest(0.9)(?))", field(s, ^field), field(s, ^field)))

  defp stat(:p99, field),
    do: dynamic([s], fragment("if(count(?) = 0, NULL, quantileTDigest(0.99)(?))", field(s, ^field), field(s, ^field)))

  defp nest_phases(row) do
    phases = for {phase, _field} <- @phases, into: %{}, do: {phase, Map.new(@stats, &{&1, row[:"#{phase}_#{&1}"]})}
    Map.merge(%{invocations: row.invocations, actions: row.actions}, phases)
  end

  defp bucket_period(opts) do
    since = Keyword.fetch!(opts, :since)
    # `until` is exclusive; the last bucket is the one holding its final second.
    last = NaiveDateTime.add(Keyword.fetch!(opts, :until), -1)
    {DateTime.from_naive!(since, "Etc/UTC"), DateTime.from_naive!(last, "Etc/UTC")}
  end

  defp observations(project_id, opts) do
    since = Keyword.fetch!(opts, :since)
    until = Keyword.fetch!(opts, :until)

    if NaiveDateTime.diff(until, since, :day) > 90,
      do: raise(ArgumentError, "execution diagnostics are limited to 90 days")

    # @query_opts keep predicates out of PREWHERE, so WHERE filters the current
    # (FINAL) invocation rows rather than superseded ones.
    invocations =
      from(i in Invocation,
        hints: ["FINAL"],
        where: i.project_id == ^project_id,
        where: i.finished_at >= ^since and i.finished_at < ^until,
        select: map(i, [:invocation_id, :command, :target_patterns, :status, :duration_ms, :is_ci, :finished_at])
      )

    # Steps and profiles are ordered by (project_id, invocation_id), so limiting
    # them to the period's invocations reads only those granules instead of the
    # project's whole retention.
    invocation_ids = from(i in subquery(invocations), select: i.invocation_id)

    # Never aggregate unpublished or superseded profile versions.
    profiles =
      from(p in Profile,
        hints: ["FINAL"],
        where: p.project_id == ^project_id and p.invocation_id in subquery(invocation_ids),
        select: %{invocation_id: p.invocation_id, version: fragment("JSONExtractString(?, 'steps_version')", p.payload)}
      )

    # No FINAL: every ingest writes its steps under a version of its own, so a
    # published version has no duplicate rows to collapse. FINAL would also keep
    # the phase filter out of PREWHERE and merge every step of the period across
    # all parts at once, which exceeds the memory limit for busy projects.
    query =
      from(s in ProfileSteps,
        join: p in subquery(profiles),
        on: p.invocation_id == s.invocation_id and p.version == s.version,
        join: i in subquery(invocations),
        on: i.invocation_id == s.invocation_id,
        where: s.project_id == ^project_id and s.invocation_id in subquery(invocation_ids),
        where:
          not is_nil(s.remote_queue_ms) or not is_nil(s.remote_input_fetch_ms) or
            not is_nil(s.remote_execution_ms) or not is_nil(s.remote_output_upload_ms)
      )

    filter_environment(query, Keyword.get(opts, :environment))
  end

  defp filter_environment(query, "ci"), do: where(query, [_s, _p, i], i.is_ci == true)
  defp filter_environment(query, "local"), do: where(query, [_s, _p, i], i.is_ci == false)
  defp filter_environment(query, _environment), do: query
end
