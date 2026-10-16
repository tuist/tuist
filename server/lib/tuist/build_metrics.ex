defmodule Tuist.BuildMetrics do
  @moduledoc """
  Project-scoped build health for Grafana. Rates and percentiles are
  aggregated from builds, never from bucket summaries. Cache savings use explicit
  report metadata. Failure categories use metadata or recorded failure evidence;
  absent evidence remains unknown.
  """

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.ClickHouseRepo
  alias Tuist.Repo

  @metrics ~w(builds successful_builds failed_builds cancelled_builds success_rate average p50 p90 p99 slow_build_threshold builds_needing_attention cache_time_saved cache_time_saved_samples cache_work_avoided cache_work_avoided_samples)

  def query(project_id, opts) do
    {cohort, params} = cohort(project_id, opts)

    threshold =
      case Keyword.get(opts, :slow_build_threshold_ms) do
        nil -> percentile_sql(params, 0.9)
        _ -> "{slow_build_threshold_ms:UInt64}"
      end

    threshold_source = if Keyword.has_key?(opts, :slow_build_threshold_ms), do: "", else: " FROM cohort"
    prefix = "WITH cohort AS (#{cohort}), thresholds AS (SELECT #{threshold} AS slow_threshold#{threshold_source}) "

    case Keyword.get(opts, :view, "series") do
      "recent_failures" -> recent_failures(prefix, params)
      "failures" -> failures(prefix, params, opts)
      "workloads" -> workloads(prefix, params)
      view -> metrics(prefix, params, opts, view)
    end
  end

  def dimension_values(project_id, dimension, build_system \\ "gradle", opts \\ [lookback_days: 90])
      when dimension in ["git_branch", "workload"] and build_system in ["gradle", "xcode", "bazel", "once"] do
    {source, params} = source(project_id, build_system: build_system)

    {time_filter, params} =
      if opts[:lookback_days] do
        start_at = DateTime.add(DateTime.utc_now(), -opts[:lookback_days], :day)

        {"AND inserted_at >= {dimension_start_datetime:DateTime64(6)}",
         Map.put(params, :dimension_start_datetime, start_at)}
      else
        {"", params}
      end

    query =
      "SELECT DISTINCT #{dimension} AS value FROM (#{source}) AS builds WHERE #{dimension} != '' #{time_filter} ORDER BY value LIMIT 1000"

    {:ok, %{rows: rows}} = execute(query, params)
    Enum.map(rows, fn [value] -> value end)
  end

  defp cohort(project_id, opts) do
    filters =
      Enum.flat_map([:is_ci, :git_branch, :workload, :status], fn key ->
        case Keyword.get(opts, key) do
          nil ->
            []

          value ->
            type = if is_boolean(value), do: "Bool", else: "String"
            ["AND #{key} = {#{key}:#{type}}"]
        end
      end)

    {source, params} = source(project_id, opts)

    query = """
    SELECT * FROM (#{source}) AS builds
    WHERE inserted_at >= {start_datetime:DateTime64(6)}
      AND inserted_at < {end_datetime:DateTime64(6)}
      #{Enum.join(filters, " ")}
    """

    {query, params}
  end

  defp source(project_id, opts) do
    system = Keyword.get(opts, :build_system, "gradle")
    params = opts |> Map.new() |> Map.put(:project_id, project_id) |> Map.put(:build_system, system)
    if system == "once", do: {once_source(opts), params}, else: {clickhouse_source(system, opts), params}
  end

  defp clickhouse_source(system, opts) do
    {table, duration, started, tasks, workload, user, status, extra} =
      case system do
        "gradle" ->
          {"gradle_builds", "duration_ms", "coalesce(started_at, inserted_at)", "requested_tasks", workload_sql(),
           "account_id", "toString(status)", ""}

        "xcode" ->
          {"build_runs FINAL", "toInt64(duration)", "inserted_at", "[scheme]",
           "if(custom_values['tuist.workload'] != '', custom_values['tuist.workload'], if(scheme != '', scheme, 'Other'))",
           "account_id", "status", "AND status IN ('success', 'failure')"}

        "bazel" ->
          {"bazel_invocations FINAL", "duration_ms", "started_at", "target_patterns",
           "if(custom_values['tuist.workload'] != '', custom_values['tuist.workload'], command)", "toInt64(0)",
           "if(command != 'run' AND exit_code == 8, 'cancelled', toString(status))",
           "AND command IN ('build', 'test', 'run', 'coverage')"}
      end

    category = failure_category_sql(system, opts)

    """
    SELECT #{if system == "bazel", do: "invocation_id", else: "toString(id)"} AS id, #{duration} AS duration_ms, #{started} AS started_at,
      inserted_at, #{user} AS account_id, #{tasks} AS requested_tasks,
      #{if system == "bazel", do: "custom_values['tuist.reported_user']", else: "''"} AS reported_user,
      #{workload} AS workload, #{category} AS failure_category, git_branch, is_ci,
      #{status} AS status,
      if(match(custom_values['tuist.cache_time_saved_ms'], '^[0-9]+$')
        AND length(custom_values['tuist.cache_time_saved_ms']) <= 11
        AND toUInt64OrNull(custom_values['tuist.cache_time_saved_ms']) <= 31536000000,
        toUInt64OrNull(custom_values['tuist.cache_time_saved_ms']), NULL) AS cache_time_saved_ms,
      if(#{if system == "gradle", do: "true", else: "false"} AND match(custom_values['tuist.cache_work_avoided_ms'], '^[0-9]+$')
        AND length(custom_values['tuist.cache_work_avoided_ms']) <= 11
        AND toUInt64OrNull(custom_values['tuist.cache_work_avoided_ms']) <= 31536000000,
        toUInt64OrNull(custom_values['tuist.cache_work_avoided_ms']), NULL) AS cache_work_avoided_ms
    FROM #{table} WHERE project_id = {project_id:Int64} #{extra} #{source_filters(system, opts)}
    """
  end

  # Use the same classification as Grafana, exposing a virtual column before
  # database filtering, ordering and pagination. No category is stored on a run.
  defmacro with_failure_category(query, system, project_id) do
    if system == "once" do
      expression = once_failure_category_sql(view: "failures")
      expression = String.replace(expression, "once_runs.id", "?")
      expression = String.replace(expression, "{project_id:Int64}", "?")
      expression = String.replace(expression, "failed_test_cases", "?")
      expression = "CASE WHEN ? = 'finalized' AND ? <> 0 AND coalesce(?, '') = '' THEN " <> expression <> " ELSE '' END"

      quote do
        _ = unquote(project_id)

        classified =
          Ecto.Query.from(b in unquote(query),
            select_merge: %{
              failure_category:
                fragment(
                  unquote(expression),
                  b.finalization,
                  b.exit_status,
                  b.cancellation_reason,
                  b.id,
                  b.project_id,
                  b.failed_test_cases,
                  b.id,
                  b.project_id
                )
            }
          )

        Ecto.Query.from(b in subquery(classified))
      end
    else
      expression = system |> failure_category_sql(view: "listing") |> String.replace("?", "\\?")
      parameter_count = length(String.split(expression, "{project_id:Int64}")) - 1
      expression = String.replace(expression, "{project_id:Int64}", "?")

      guard =
        if system == "bazel",
          do: "status = 'failure' AND NOT (command != 'run' AND exit_code = 8)",
          else: "status = 'failure'"

      expression = "if(" <> guard <> ", " <> expression <> ", '')"
      parameters = List.duplicate(quote(do: ^unquote(project_id)), parameter_count)
      fragment = {:fragment, [], [expression | parameters]}

      quote do
        _ = unquote(project_id)
        classified = Ecto.Query.from(b in unquote(query), select_merge: %{failure_category: unquote(fragment)})
        Ecto.Query.from(b in subquery(classified))
      end
    end
  end

  def failure_category(project_id, build_system, build_id) do
    {source, params} = source(project_id, build_system: build_system, view: "listing", build_id: build_id)
    id = if build_system == "once", do: "id::text", else: "id"

    sql =
      "SELECT failure_category FROM (#{source}) AS builds WHERE status = 'failure' AND #{id} = {build_id:String} LIMIT 1"

    case execute(sql, params) do
      {:ok, %{rows: [[category]]}} -> category
      {:ok, %{rows: []}} -> nil
    end
  end

  defp failure_category_sql(system, opts) do
    evidence = failure_evidence_sql(system, opts)

    infrastructure =
      if system == "bazel", do: "command != 'run' AND exit_code IN (2, 32, 33, 34, 36, 37, 38, 39, 45)", else: "false"

    """
    multiIf(custom_values['tuist.failure_category'] IN ('verification', 'infrastructure_tooling'),
      custom_values['tuist.failure_category'],
      #{infrastructure}, 'infrastructure_tooling',
      custom_values['tuist.detected_failure_category'] IN ('verification', 'infrastructure_tooling'),
      custom_values['tuist.detected_failure_category'],
      #{evidence}, 'verification', 'unknown')
    """
  end

  defp failure_evidence_sql("gradle", opts) do
    if Keyword.get(opts, :view) in ["failures", "recent_failures", "listing"] do
      """
      toString(id) IN (SELECT toString(gradle_build_id) FROM gradle_tasks
        WHERE project_id = {project_id:Int64} AND outcome = 'failed'
          #{evidence_build_id(opts, "gradle_build_id")}
          AND gradle_build_id IN (SELECT id FROM gradle_builds WHERE project_id = {project_id:Int64} AND status = 'failure')
          #{evidence_period(opts)}
          AND match(task_type, '(^|[.])(Test|Checkstyle|Pmd|CodeNarc|AndroidLint[^.]*|Lint[^.]*|JavaCompile|GroovyCompile|ScalaCompile|KotlinCompile|KotlinJvmCompile|KotlinNativeCompile|SwiftCompile|CppCompile|CCompile|LinkExecutable|LinkSharedLibrary)(_Decorated)?$'))
      """
    else
      "false"
    end
  end

  defp failure_evidence_sql("xcode", opts) do
    if Keyword.get(opts, :view) in ["failures", "recent_failures", "listing"] do
      # Issues have no project column: restrict them through the authorized,
      # time-bounded build identifiers rather than scanning other tenants.
      """
      toString(id) IN (SELECT toString(build_run_id) FROM build_issues
        WHERE type = 'error'
          #{evidence_build_id(opts, "build_run_id")}
          AND step_type IN ('c_compilation', 'swift_compilation', 'swift_aggregated_compilation',
            'linker', 'compile_assets_catalog', 'compile_storyboard', 'xib_compilation',
            'precompile_bridging_header', 'merge_swift_module', 'link_storyboards')
          AND build_run_id IN (SELECT id FROM build_runs FINAL
            WHERE project_id = {project_id:Int64} AND status = 'failure'
              #{evidence_period(opts)}))
      """
    else
      "false"
    end
  end

  defp failure_evidence_sql("bazel", _opts), do: "command IN ('test', 'coverage') AND exit_code = 3"

  defp evidence_build_id(opts, field) do
    if Keyword.has_key?(opts, :build_id), do: "AND toString(#{field}) = {build_id:String}", else: ""
  end

  defp evidence_period(opts) do
    if Keyword.get(opts, :view) == "listing",
      do: "",
      else: "AND inserted_at >= {start_datetime:DateTime64(6)} AND inserted_at < {end_datetime:DateTime64(6)}"
  end

  defp once_failure_category_sql(opts) do
    if Keyword.get(opts, :view) in ["failures", "recent_failures", "listing"] do
      """
      CASE WHEN EXISTS (SELECT 1 FROM once_actions a WHERE a.once_run_id = once_runs.id
          AND a.project_id = {project_id:Int64} AND a.result = 'infrastructure_error')
        THEN 'infrastructure_tooling'
        WHEN failed_test_cases > 0 OR EXISTS (SELECT 1 FROM once_actions a
          WHERE a.once_run_id = once_runs.id AND a.project_id = {project_id:Int64}
            AND a.result = 'failed' AND a.capability IN ('compile', 'link', 'test', 'lint', 'check'))
        THEN 'verification' ELSE 'unknown' END
      """
    else
      "'unknown'"
    end
  end

  defp once_source(opts) do
    failure_category = once_failure_category_sql(opts)

    """
    SELECT run_id AS id, wall_ms AS duration_ms, started_at, started_at AS inserted_at,
      coalesce(account_id, 0)::bigint AS account_id, ARRAY[coalesce(command_display, kind)] AS requested_tasks,
      '' AS reported_user, kind AS workload, coalesce(git_branch, '') AS git_branch, is_ci,
      CASE WHEN nullif(cancellation_reason, '') IS NOT NULL THEN 'cancelled'
        WHEN exit_status = 0 THEN 'success' ELSE 'failure' END AS status,
      #{failure_category} AS failure_category,
      NULL::bigint AS cache_time_saved_ms, NULL::bigint AS cache_work_avoided_ms
    FROM once_runs WHERE project_id = {project_id:Int64}
      AND finalization = 'finalized' AND (exit_status IS NOT NULL OR nullif(cancellation_reason, '') IS NOT NULL)
      AND kind IN ('build', 'test', 'generic') #{source_filters("once", opts)}
    """
  end

  defp source_filters(system, opts) do
    keys =
      case system do
        "xcode" -> [:scheme, :configuration, :category]
        "bazel" -> [:command]
        "once" -> [:kind]
        _ -> []
      end

    filters =
      Enum.flat_map(keys, fn key ->
        if Keyword.has_key?(opts, key), do: ["AND #{key} = {#{key}:String}"], else: []
      end)

    filters =
      if system == "xcode" && Keyword.has_key?(opts, :tag),
        do: ["AND has(custom_tags, {tag:String})" | filters],
        else: filters

    Enum.join(filters, " ")
  end

  def cache_work_avoided(build) do
    value = (build.custom_values || %{})["tuist.cache_work_avoided_ms"]

    if is_binary(value) && Regex.match?(~r/^[0-9]{1,11}$/, value) do
      milliseconds = String.to_integer(value)
      if milliseconds <= 31_536_000_000, do: milliseconds
    end
  end

  defp workload_sql do
    """
    multiIf(
      custom_values['tuist.workload'] != '', custom_values['tuist.workload'],
      arrayExists(t -> match(lower(t), '(^|:)(connected|device|manageddevice).*test|(^|:)[^:]*androidtest$'), requested_tasks), 'Instrumented tests',
      arrayExists(t -> match(lower(t), '(^|:)test'), requested_tasks), 'Unit tests',
      arrayExists(t -> match(lower(t), '(^|:)(lint|check|detekt|ktlint)'), requested_tasks), 'Lint / checks',
      arrayExists(t -> match(lower(t), '(^|:)(assemble|bundle|package)'), requested_tasks), 'Assemble / package',
      'Other')
    """
  end

  defp select_metrics(params) do
    if params.build_system == "once", do: postgres_metrics(), else: clickhouse_metrics()
  end

  defp clickhouse_metrics do
    """
    count() AS builds,
    countIf(status = 'success') AS successful_builds,
    countIf(status = 'failure') AS failed_builds,
    countIf(status = 'cancelled') AS cancelled_builds,
    if(countIf(status IN ('success', 'failure')) = 0, NULL,
      100.0 * countIf(status = 'success') / countIf(status IN ('success', 'failure'))) AS success_rate,
    avgOrNull(duration_ms) AS average,
    quantileExactInclusiveOrNull(0.5)(duration_ms) AS p50,
    quantileExactInclusiveOrNull(0.9)(duration_ms) AS p90,
    quantileExactInclusiveOrNull(0.99)(duration_ms) AS p99,
    (SELECT slow_threshold FROM thresholds) AS slow_build_threshold,
    countIf(status = 'failure' OR duration_ms > (SELECT slow_threshold FROM thresholds)) AS builds_needing_attention,
    if(count(cache_time_saved_ms) = 0, NULL, sum(cache_time_saved_ms)) AS cache_time_saved,
    count(cache_time_saved_ms) AS cache_time_saved_samples,
    if(count(cache_work_avoided_ms) = 0, NULL, sum(cache_work_avoided_ms)) AS cache_work_avoided,
    count(cache_work_avoided_ms) AS cache_work_avoided_samples
    """
  end

  defp metrics(prefix, params, opts, view) do
    {:ok, %{rows: [totals]}} = execute(prefix <> "SELECT #{select_metrics(params)} FROM cohort", params)
    totals = Map.new(Enum.zip(@metrics, totals))

    if view == "total" do
      %{totals: totals}
    else
      {interval, step} = bucket_interval(opts)

      query =
        prefix <>
          """
          SELECT #{bucket_sql(params, interval, step)} AS date,
            #{select_metrics(params)} FROM cohort GROUP BY date ORDER BY date
          """

      {:ok, %{rows: rows}} = execute(query, params)
      by_date = Map.new(rows, fn [date | values] -> {date, Map.new(Enum.zip(@metrics, values))} end)
      dates = bucket_dates(opts, step)
      empty = Map.new(@metrics, fn metric -> {metric, if(metric in count_metrics(), do: 0)} end)
      empty = Map.put(empty, "slow_build_threshold", totals["slow_build_threshold"])

      series =
        Map.new(@metrics, fn metric ->
          {metric, Enum.map(dates, &Map.get(by_date, &1, empty)[metric])}
        end)

      reported_dates =
        if opts[:clip_series_start] do
          Enum.map(dates, &max(&1, DateTime.to_unix(opts[:start_datetime])))
        else
          dates
        end

      %{dates: reported_dates, series: series, totals: totals}
    end
  end

  defp count_metrics do
    ~w(builds successful_builds failed_builds cancelled_builds builds_needing_attention cache_time_saved_samples cache_work_avoided_samples)
  end

  defp bucket_interval(opts) do
    seconds = DateTime.diff(opts[:end_datetime], opts[:start_datetime])

    cond do
      seconds <= 86_400 -> {"1 HOUR", :hour}
      seconds >= 60 * 86_400 -> {"1 MONTH", :month}
      true -> {"1 DAY", :day}
    end
  end

  defp bucket_dates(opts, step) do
    start_at = opts[:start_datetime]
    end_at = opts[:end_datetime]

    first =
      case step do
        :hour -> %{start_at | minute: 0, second: 0, microsecond: {0, 0}}
        :day -> DateTime.new!(DateTime.to_date(start_at), ~T[00:00:00])
        :month -> DateTime.new!(%{DateTime.to_date(start_at) | day: 1}, ~T[00:00:00])
      end

    first
    |> Stream.iterate(&next_bucket(&1, step))
    |> Enum.take_while(&DateTime.before?(&1, end_at))
    |> Enum.map(&DateTime.to_unix/1)
  end

  defp next_bucket(date, :hour), do: DateTime.add(date, 3600)
  defp next_bucket(date, :day), do: DateTime.add(date, 86_400)

  defp next_bucket(date, :month) do
    next = date |> DateTime.to_date() |> Date.end_of_month() |> Date.add(1)
    DateTime.new!(next, ~T[00:00:00])
  end

  defp workloads(prefix, params) do
    {:ok, %{rows: rows}} =
      execute(
        prefix <> "SELECT workload, #{select_metrics(params)} FROM cohort GROUP BY workload ORDER BY workload LIMIT 1000",
        params
      )

    %{
      rows:
        Enum.map(rows, fn [workload | values] -> Map.put(Map.new(Enum.zip(@metrics, values)), "workload", workload) end)
    }
  end

  defp failures(prefix, params, opts) do
    {:ok, %{rows: rows}} =
      execute(
        prefix <> "SELECT failure_category, count() FROM cohort WHERE status = 'failure' GROUP BY failure_category",
        params
      )

    counts = Map.new(rows, fn [category, count] -> {category, count} end)
    rows = Enum.map(~w(verification infrastructure_tooling unknown), &%{category: &1, builds: Map.get(counts, &1, 0)})

    rows =
      if opts[:include_failure_total], do: [%{category: "all", builds: Enum.sum(Map.values(counts))} | rows], else: rows

    %{rows: rows}
  end

  defp recent_failures(prefix, params) do
    {:ok, %{rows: rows}} =
      execute(
        prefix <>
          """
          SELECT id, #{timestamp_sql(params, "started_at")}, duration_ms,
            account_id, requested_tasks, workload, failure_category, git_branch, reported_user
          FROM cohort WHERE status = 'failure' ORDER BY inserted_at DESC, id DESC LIMIT 100
          """,
        params
      )

    account_ids = rows |> Enum.map(&Enum.at(&1, 3)) |> Enum.uniq()
    accounts = Map.new(Repo.all(from a in Account, where: a.id in ^account_ids, select: {a.id, a.name}))

    %{
      rows:
        Enum.map(rows, fn [id, started_at, duration, account_id, tasks, workload, category, branch, reported_user] ->
          %{
            id: id,
            build_system: params.build_system,
            started_at: started_at,
            duration_ms: duration,
            user: Map.get(accounts, account_id, if(reported_user == "", do: "Unknown", else: reported_user)),
            requested_tasks: tasks,
            workload: workload,
            failure_category: category,
            git_branch: branch
          }
        end)
    }
  end

  defp percentile_sql(%{build_system: "once"}, percentile),
    do: "percentile_cont(#{percentile}) WITHIN GROUP (ORDER BY duration_ms)"

  defp percentile_sql(_params, percentile), do: "quantileExactInclusiveOrNull(#{percentile})(duration_ms)"

  defp postgres_metrics do
    """
    count(*) AS builds,
    count(*) FILTER (WHERE status = 'success') AS successful_builds,
    count(*) FILTER (WHERE status = 'failure') AS failed_builds,
    count(*) FILTER (WHERE status = 'cancelled') AS cancelled_builds,
    100.0 * count(*) FILTER (WHERE status = 'success') / NULLIF(count(*) FILTER (WHERE status IN ('success', 'failure')), 0) AS success_rate,
    avg(duration_ms)::double precision AS average,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY duration_ms) AS p50,
    percentile_cont(0.9) WITHIN GROUP (ORDER BY duration_ms) AS p90,
    percentile_cont(0.99) WITHIN GROUP (ORDER BY duration_ms) AS p99,
    (SELECT slow_threshold FROM thresholds) AS slow_build_threshold,
    count(*) FILTER (WHERE status = 'failure' OR duration_ms > (SELECT slow_threshold FROM thresholds)) AS builds_needing_attention,
    sum(cache_time_saved_ms)::double precision AS cache_time_saved,
    count(cache_time_saved_ms) AS cache_time_saved_samples,
    sum(cache_work_avoided_ms)::double precision AS cache_work_avoided,
    count(cache_work_avoided_ms) AS cache_work_avoided_samples
    """
  end

  defp timestamp_sql(%{build_system: "once"}, column), do: "extract(epoch FROM #{column})::bigint"
  defp timestamp_sql(_params, column), do: "toUnixTimestamp(#{column})"

  defp bucket_sql(%{build_system: "once"}, _interval, step),
    do: "extract(epoch FROM date_trunc('#{step}', inserted_at, 'UTC'))::bigint"

  defp bucket_sql(_params, interval, _step),
    do: "toUnixTimestamp(toStartOfInterval(inserted_at, INTERVAL #{interval}, 'UTC'))"

  defp execute(sql, %{build_system: "once"} = params) do
    names = ~r/\{([a-z_]+):[^}]+\}/ |> Regex.scan(sql) |> Enum.map(&Enum.at(&1, 1)) |> Enum.uniq()
    values = Enum.map(names, &Map.fetch!(params, String.to_existing_atom(&1)))

    indexes = names |> Enum.with_index(1) |> Map.new()

    sql =
      Regex.replace(~r/\{([a-z_]+):([^}]+)\}/, sql, fn _, name, type ->
        cast =
          case type do
            "DateTime64(6)" -> "timestamptz"
            "Bool" -> "boolean"
            "String" -> "text"
            _ -> "bigint"
          end

        "$#{indexes[name]}::#{cast}"
      end)

    sql = String.replace(sql, "count()", "count(*)")

    case Repo.query(sql, values) do
      {:ok, result} -> {:ok, %{rows: Enum.map(result.rows, fn row -> Enum.map(row, &normalize_number/1) end)}}
      error -> error
    end
  end

  defp execute(sql, params), do: ClickHouseRepo.query(sql, Map.delete(params, :build_system))
  defp normalize_number(%Decimal{} = value), do: Decimal.to_float(value)
  defp normalize_number(value), do: value
end
