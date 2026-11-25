defmodule Tuist.RemoteExecution.RunAnalytics do
  @moduledoc """
  Per-run remote execution diagnostics for Struo projects, read from the
  gateway's action records (`Tuist.RemoteExecution.Actions`) rather than from
  build profiles, which Struo does not publish.

  Struo names the run it belongs to on every Execute request, with the same
  run ID its live run events carry, so an action's `invocation_id` is the
  `run_id` of a `Tuist.OnceEvents.Run`. Returns the shapes of
  `Tuist.RemoteExecution.Analytics`, so the Remote execution page reads both
  build systems alike. A run whose events never arrived still shows, without
  its command. Records are best effort: a missing record does not prove an
  action did not run.
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.ClickHouseTimeSeries
  alias Tuist.OnceEvents.Run
  alias Tuist.RemoteExecution.Action
  alias Tuist.Repo

  @query_opts [timeout: 25_000, settings: [max_execution_time: 20, max_memory_usage: 268_435_456]]
  @page_size 20
  @max_page 500
  @stats [:avg, :p50, :p90, :p99]
  @sort_fields ~w(ran-at duration actions execution execution-p50 execution-p90 status)

  @doc "Period totals plus avg/p50/p90/p99 per phase; a phase without measurements is nil."
  def summary(project_id, opts) do
    project_id
    |> records(opts)
    |> select(^aggregates())
    |> ClickHouseRepo.one(@query_opts)
    |> nest_phases()
  end

  @doc "The same aggregates per hour, day or month bucket of the actions' completion."
  def time_series(project_id, opts) do
    since = Keyword.fetch!(opts, :since)
    last = NaiveDateTime.add(Keyword.fetch!(opts, :until), -1)
    {start_datetime, end_datetime} = {DateTime.from_naive!(since, "Etc/UTC"), DateTime.from_naive!(last, "Etc/UTC")}
    granularity = ClickHouseTimeSeries.granularity(start_datetime, end_datetime)
    date_format = ClickHouseTimeSeries.date_format(granularity)
    bucket = dynamic([a], fragment("formatDateTime(?, ?)", a.inserted_at, ^date_format))

    rows =
      project_id
      |> records(opts)
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
  One row per run with remote actions in the period. A run is `"failure"`
  when any of its remote actions failed. `duration_ms` is the run's wall
  time when its events arrived, otherwise the span of its remote actions;
  sorting by duration always uses that span, the only figure ClickHouse has.
  `:search` matches run IDs and targets; `:filters` take Flop-style maps for
  `:status`, `:target_patterns` (the actions' targets) and `:actions`.
  """
  def activity(project_id, opts) do
    page = min(Keyword.get(opts, :page, 1), @max_page)
    search = Keyword.get(opts, :search, "")
    sort_by = if(Keyword.get(opts, :sort_by) in @sort_fields, do: Keyword.get(opts, :sort_by), else: "ran-at")
    direction = if Keyword.get(opts, :sort_order) == "asc", do: :asc, else: :desc

    query =
      select_merge(
        from(a in records(project_id, opts),
          group_by: a.invocation_id,
          select: %{
            invocation_id: a.invocation_id,
            actions: count(),
            failed_actions: fragment("countIf(? != 0 OR ? != 0)", a.status_code, a.exit_code),
            targets: fragment("groupUniqArray(10)(?)", a.target),
            finished_at: fragment("max(coalesce(?, ?))", a.worker_completed_at, a.inserted_at)
          }
        ),
        ^Map.put(execution_stats(), :span_ms, span())
      )

    query =
      if search == "",
        do: query,
        else:
          where(
            query,
            [a],
            fragment("positionCaseInsensitiveUTF8(?, ?) > 0", a.invocation_id, ^search) or
              fragment("positionCaseInsensitiveUTF8(?, ?) > 0", a.target, ^search)
          )

    query = Enum.reduce(Keyword.get(opts, :filters, []), query, &filter/2)

    rows =
      query
      |> order_by(^[{direction, sort_expression(sort_by)}, {:asc, dynamic([a], a.invocation_id)}])
      |> limit(@page_size + 1)
      |> offset(^((page - 1) * @page_size))
      |> ClickHouseRepo.all(@query_opts)

    shown = Enum.take(rows, @page_size)
    runs = runs(project_id, Enum.map(shown, & &1.invocation_id))

    %{
      rows: Enum.map(shown, &row(&1, Map.get(runs, &1.invocation_id))),
      page: page,
      has_next_page?: length(rows) > @page_size and page < @max_page
    }
  end

  defp row(row, run) do
    row
    |> Map.merge(%{
      status: if(row.failed_actions == 0, do: "success", else: "failure"),
      duration_ms: (run && run.wall_ms) || row.span_ms,
      command: run && run.command_display,
      target_patterns: Enum.reject(row.targets, &(&1 == "")),
      run: run
    })
    |> Map.update!(:finished_at, &DateTime.from_naive!(&1, "Etc/UTC"))
  end

  defp runs(_project_id, []), do: %{}

  defp runs(project_id, run_ids) do
    from(r in Run, where: r.project_id == ^project_id and r.run_id in ^run_ids)
    |> Repo.all()
    |> Map.new(&{&1.run_id, &1})
  end

  defp filter(%{field: :status, op: op, value: value}, query) when op in [:==, :!=] and value in ["success", "failure"] do
    failed? = value == "failure" == (op == :==)

    if failed?,
      do: having(query, [a], fragment("countIf(? != 0 OR ? != 0) > 0", a.status_code, a.exit_code)),
      else: having(query, [a], fragment("countIf(? != 0 OR ? != 0) = 0", a.status_code, a.exit_code))
  end

  defp filter(%{field: :target_patterns, op: op, value: value}, query) when is_binary(value) and value != "" do
    matches = dynamic([a], fragment("countIf(positionCaseInsensitiveUTF8(?, ?) > 0)", a.target, ^value))
    if op == :=~ or op == :==, do: having(query, ^dynamic(^matches > 0)), else: having(query, ^dynamic(^matches == 0))
  end

  defp filter(%{field: :actions, op: op, value: value}, query) when op in [:==, :<, :>, :<=, :>=] do
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

  # Struo reports no command filterable here; other filters do not apply.
  defp filter(_filter, query), do: query

  defp sort_expression("status"), do: dynamic([a], fragment("countIf(? != 0 OR ? != 0) = 0", a.status_code, a.exit_code))

  defp sort_expression("duration"), do: span()
  defp sort_expression("actions"), do: dynamic(fragment("count()"))
  defp sort_expression("execution"), do: stat(:avg, execution_ms())

  defp sort_expression("execution-" <> stat) when stat in ~w(p50 p90),
    do: stat(String.to_existing_atom(stat), execution_ms())

  defp sort_expression(_ran_at), do: dynamic([a], fragment("max(coalesce(?, ?))", a.worker_completed_at, a.inserted_at))

  defp span do
    dynamic(
      [a],
      fragment(
        "toUnixTimestamp64Milli(max(coalesce(?, ?))) - toUnixTimestamp64Milli(min(coalesce(?, ?, ?)))",
        a.worker_completed_at,
        a.inserted_at,
        a.queued_at,
        a.worker_start_at,
        a.inserted_at
      )
    )
  end

  defp execution_stats,
    do: for(stat <- [:avg, :p50, :p90], into: %{}, do: {execution_key(stat), stat(stat, execution_ms())})

  defp execution_key(:avg), do: :execution_ms
  defp execution_key(stat), do: :"execution_#{stat}_ms"

  # Nullable when either timestamp is unavailable, so `count` skips it.
  defp queue_ms,
    do: dynamic([a], fragment("toUnixTimestamp64Milli(?) - toUnixTimestamp64Milli(?)", a.worker_start_at, a.queued_at))

  defp execution_ms,
    do:
      dynamic(
        [a],
        fragment("toUnixTimestamp64Milli(?) - toUnixTimestamp64Milli(?)", a.execution_completed_at, a.execution_start_at)
      )

  defp aggregates do
    base = %{
      invocations: dynamic([a], fragment("uniqExact(?)", a.invocation_id)),
      actions: dynamic(fragment("count()"))
    }

    for {phase, value} <- [queue: queue_ms(), execution: execution_ms()], stat <- @stats, into: base do
      {:"#{phase}_#{stat}", stat(stat, value)}
    end
  end

  defp stat(:avg, value), do: dynamic(fragment("if(count(?) = 0, NULL, avg(?))", ^value, ^value))

  # ClickHouse takes an aggregate's parameters only as literals.
  defp stat(:p50, value), do: dynamic(fragment("if(count(?) = 0, NULL, quantileTDigest(0.5)(?))", ^value, ^value))
  defp stat(:p90, value), do: dynamic(fragment("if(count(?) = 0, NULL, quantileTDigest(0.9)(?))", ^value, ^value))
  defp stat(:p99, value), do: dynamic(fragment("if(count(?) = 0, NULL, quantileTDigest(0.99)(?))", ^value, ^value))

  defp nest_phases(row) do
    phases = for phase <- [:queue, :execution], into: %{}, do: {phase, Map.new(@stats, &{&1, row[:"#{phase}_#{&1}"]})}
    Map.merge(%{invocations: row.invocations, actions: row.actions}, phases)
  end

  # Cached results the service answered from the action cache never ran.
  defp records(project_id, opts) do
    since = Keyword.fetch!(opts, :since)
    until = Keyword.fetch!(opts, :until)

    if NaiveDateTime.diff(until, since, :day) > 90,
      do: raise(ArgumentError, "execution diagnostics are limited to 90 days")

    query =
      from(a in Action,
        hints: ["FINAL"],
        where: a.project_id == ^project_id,
        where: a.inserted_at >= ^since and a.inserted_at < ^until,
        where: a.cached_result == false
      )

    filter_environment(query, Keyword.get(opts, :environment))
  end

  # Records do not carry the environment; every run is included.
  defp filter_environment(query, _environment), do: query
end
