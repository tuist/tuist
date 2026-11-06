defmodule Tuist.Tests.Selections do
  @moduledoc """
  The reads behind coverage-based test selection's pages. Each `tuist test`
  invocation that asked for a selection has an impact run
  (`Tuist.TestImpactAnalysis.Run`): the diff it used against its baseline,
  the nearest ancestor whose full run recorded per-test coverage evidence,
  the outcome (`selected`, or `fallback` when it continued as default
  selective testing), the trace of the rules that decided it and the
  counts. Only the tests it selected are stored
  (`Tuist.TestImpactAnalysis.RunTest`); the skipped ones are the baseline
  run's tests in the requested modules, minus the selected ones. The test
  runs an invocation reported point to its impact run (`test_impact_run_id`).

  These back the Test Selection page and the Selective Testing tabs of a
  test run and a test case run.
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.GitHistory
  alias Tuist.Shards.ShardPlan
  alias Tuist.Shards.ShardPlanTestSuite
  alias Tuist.TestImpactAnalysis.Run
  alias Tuist.TestImpactAnalysis.RunTest
  alias Tuist.TestImpactAnalysis.Storage
  alias Tuist.Tests.Coverage.ExcludedPaths
  alias Tuist.Tests.CoverageFile
  alias Tuist.Tests.CoverageRun
  alias Tuist.Tests.Test
  alias Tuist.Tests.TestCaseRun

  @selected_reasons ~w(test_file_changed failed_last_run no_evidence impacted owned_without_evidence undecided)
  @skipped_reasons ~w(unaffected module_skipped)
  @fallback_reasons ~w(no_baseline baseline_too_old no_baseline_evidence history_unavailable tracked_file_changed diff_too_large diff_unavailable history_unknown)

  @doc "Why an impact run selects a test (`RunTest.reason`), in the rules' order."
  def selected_reasons, do: @selected_reasons

  @doc "Why an impact run skips a test."
  def skipped_reasons, do: @skipped_reasons

  @doc "Why an impact run fell back to default selective testing (`Run.reason`)."
  def fallback_reasons, do: @fallback_reasons

  @doc "Whether the impact run fell back to default selective testing."
  def fallback?(%{outcome: outcome}), do: outcome == "fallback"

  @doc """
  Whether an impact run reads by module rather than by test: one that stored
  no test counts, such as a fallback to default selective testing that ended
  before the baseline. One that found a baseline counts the tests in the
  modules hashing skipped and reads like any selection.
  """
  def counted_by_module?(%Run{} = run), do: run.requested_count == 0 and module_counts(run).total > 0

  @doc """
  Whether an impact run fell back to default selective testing after finding
  its baseline: coverage decided no test, every test in the modules hashing
  left ran, and the run reads like a selection, its tests derived from the
  baseline.
  """
  def counted_fallback?(%Run{} = run), do: fallback?(run) and run.requested_count > 0

  @doc "Whether an impact run shows as a selection: one, or a fallback that found its baseline."
  def selection?(%Run{} = run), do: not fallback?(run) or counted_fallback?(run)

  @doc """
  The test modules an impact run ran out of those requested: the ones hashing
  left, out of those plus the ones it skipped. What a fallback to default
  selective testing is measured by, since it decides no test.
  """
  def module_counts(%Run{requested_modules: requested, skipped_modules: skipped}),
    do: %{ran: length(requested), total: length(requested) + map_size(skipped)}

  @doc "The share of an impact run's test modules hashing skipped."
  def module_skip_rate(%Run{} = run) do
    %{ran: ran, total: total} = module_counts(run)
    skip_rate(ran, total - ran)
  end

  # The mean of the runs' skip rates, each as `skip_rate/1` computes it, as a
  # fraction.
  defmacrop run_skip_rate_avg(r) do
    quote do
      fragment(
        "avg(multiIf(? > 0, ? / ?, length(?) + length(mapKeys(?)) > 0, length(mapKeys(?)) / (length(?) + length(mapKeys(?))), 0))",
        unquote(r).requested_count,
        unquote(r).skipped_count,
        unquote(r).requested_count,
        unquote(r).requested_modules,
        unquote(r).skipped_modules,
        unquote(r).skipped_modules,
        unquote(r).requested_modules,
        unquote(r).skipped_modules
      )
    end
  end

  @doc """
  The project's impact runs over a period, counting only those a test run
  reported: totals, their trend against the
  period before, and per-bucket series (hours for a period of two days or
  less, days otherwise) of runs, selected and skipped tests, and skip rate.
  The end is carried to the close of its second, as the date picker's
  periods are in whole seconds.
  """
  def analytics(project_id, {start_datetime, end_datetime}) do
    until = DateTime.add(end_datetime, 1, :second)
    bucket = bucket(start_datetime, end_datetime)
    format = bucket_format(bucket)

    rows =
      from(r in reported_runs(project_id, start_datetime, until),
        group_by: fragment("formatDateTime(?, ?)", r.inserted_at, ^format),
        select: %{
          date: fragment("formatDateTime(?, ?)", r.inserted_at, ^format),
          runs: count(),
          selected: sum(r.selected_count),
          skipped: sum(r.skipped_count),
          skip_rate: run_skip_rate_avg(r)
        }
      )
      |> ClickHouseRepo.all()
      |> Map.new(&{&1.date, &1})

    points =
      start_datetime
      |> buckets(end_datetime, bucket)
      |> Enum.map(fn {date, key} ->
        row = Map.get(rows, key, %{runs: 0, selected: 0, skipped: 0, skip_rate: 0.0})

        %{
          date: date,
          runs: to_integer(row.runs),
          selected: to_integer(row.selected),
          skipped: to_integer(row.skipped),
          skip_rate: percentage(row.runs, row.skip_rate)
        }
      end)

    span = DateTime.diff(end_datetime, start_datetime, :second)
    current = totals(project_id, start_datetime, until)
    previous = totals(project_id, DateTime.add(start_datetime, -span, :second), start_datetime)

    %{
      totals: current,
      trends: Map.new(~w(runs selected skipped skip_rate)a, &{&1, trend(Map.get(previous, &1), Map.get(current, &1))}),
      dates: Enum.map(points, & &1.date),
      runs: Enum.map(points, & &1.runs),
      selected: Enum.map(points, & &1.selected),
      skipped: Enum.map(points, & &1.skipped),
      skip_rates: Enum.map(points, & &1.skip_rate)
    }
  end

  defp totals(project_id, start_datetime, until) do
    row =
      ClickHouseRepo.one(
        from(r in reported_runs(project_id, start_datetime, until),
          select: %{
            runs: count(),
            fallbacks: fragment("countIf(? = 'fallback')", r.outcome),
            selected: sum(r.selected_count),
            skipped: sum(r.skipped_count),
            skip_rate: run_skip_rate_avg(r)
          }
        )
      ) || %{}

    %{
      runs: to_integer(row[:runs]),
      fallbacks: to_integer(row[:fallbacks]),
      selected: to_integer(row[:selected]),
      skipped: to_integer(row[:skipped]),
      skip_rate: percentage(row[:runs], row[:skip_rate])
    }
  end

  defp percentage(runs, fraction) do
    if to_integer(runs) == 0 or not is_number(fraction), do: 0.0, else: Float.round(fraction * 100, 1)
  end

  @doc "The share of tests that were skipped, as a percentage with one decimal."
  def skip_rate(selected, skipped) do
    case selected + skipped do
      0 -> 0.0
      total -> Float.round(skipped / total * 100, 1)
    end
  end

  @doc """
  An impact run's skip rate: its skipped tests, those in the modules hashing
  skipped included, out of its requested ones, and the share of modules
  hashing skipped for a run that stored no test counts.
  """
  def skip_rate(%Run{} = run) do
    if counted_by_module?(run),
      do: module_skip_rate(run),
      else: skip_rate(run.selected_count, run.skipped_count)
  end

  @doc "The tests coverage skipped in the modules hashing left: the `unaffected` rule's skips."
  def unaffected_count(%Run{rule_trace: trace}) do
    Enum.find_value(trace, 0, fn entry -> if entry.rule == "unaffected", do: entry.skipped end)
  end

  @doc "The tests skipped because hashing found their module not changed."
  def module_skipped_count(%Run{skipped_modules: modules}), do: modules |> Map.values() |> Enum.sum()

  @doc """
  The modules hashing found not changed, each with its number of tests in the
  baseline, the largest first.
  """
  def skipped_modules(%Run{skipped_modules: modules}) do
    modules
    |> Enum.map(fn {module_name, tests} -> %{module_name: module_name, tests: tests} end)
    |> Enum.sort_by(&{-&1.tests, &1.module_name})
  end

  defp trend(previous, current) when previous in [0, +0.0] or current in [0, +0.0], do: 0.0
  defp trend(previous, current), do: Float.round((current - previous) / previous * 100, 1)

  defp bucket(start_datetime, end_datetime) do
    if DateTime.diff(end_datetime, start_datetime, :hour) <= 48, do: :hour, else: :day
  end

  defp bucket_format(:hour), do: "%Y-%m-%d %H:00"
  defp bucket_format(:day), do: "%Y-%m-%d"

  defp buckets(start_datetime, end_datetime, :hour) do
    first = %{DateTime.truncate(start_datetime, :second) | minute: 0, second: 0}
    hours = div(DateTime.diff(end_datetime, first, :second), 3600)

    for offset <- 0..hours//1 do
      datetime = DateTime.add(first, offset, :hour)
      {datetime, Calendar.strftime(datetime, "%Y-%m-%d %H:00")}
    end
  end

  defp buckets(start_datetime, end_datetime, :day) do
    start_datetime
    |> DateTime.to_date()
    |> Date.range(DateTime.to_date(end_datetime))
    |> Enum.map(&{&1, Date.to_iso8601(&1)})
  end

  @doc """
  A page of the project's impact runs selected in `period` (`{start, end}`)
  that a test run reported, newest first, each with the id of the latest test
  run that reported it (`test_run_id`). Options: `:search` (a commit SHA
  prefix, or part of a branch, scheme or test plan name), `:page` and
  `:page_size`. Returns
  `{rows, %{current_page, total_pages, total_count}}`.
  """
  def list_runs(project_id, {start_datetime, end_datetime}, opts \\ []) do
    {rows, meta} =
      project_id
      |> reported_runs(start_datetime, DateTime.add(end_datetime, 1, :second))
      |> filter_run_search(Keyword.get(opts, :search))
      |> order_by([r], desc: r.inserted_at, desc: r.id)
      |> select([r, t], {r, t.test_run_id})
      |> paginate(opts)

    {Enum.map(rows, fn {run, test_run_id} -> Map.put(run, :test_run_id, test_run_id) end), meta}
  end

  # The impact runs selected in [start, until) that a test run points to,
  # joined to the latest such test run: an impact run whose client gave up
  # waiting is still written, but no test run points to it. Test runs are
  # read from the period on, as one is written after its impact run, with a
  # day's margin past it for runs that finished after the period ended.
  defp reported_runs(project_id, start_datetime, until) do
    test_runs =
      from(t in Test,
        where: t.project_id == ^project_id and not is_nil(t.test_impact_run_id),
        where: t.inserted_at >= ^start_datetime and t.inserted_at < ^DateTime.add(until, 1, :day),
        group_by: t.test_impact_run_id,
        select: %{
          id: fragment("assumeNotNull(?)", t.test_impact_run_id),
          test_run_id: fragment("toString(argMax(?, ?))", t.id, t.ran_at)
        }
      )

    from(r in Run,
      join: t in subquery(test_runs),
      on: t.id == r.id,
      where: r.project_id == ^project_id and r.inserted_at >= ^start_datetime and r.inserted_at < ^until
    )
  end

  defp filter_run_search(query, search) when search in [nil, ""], do: query

  defp filter_run_search(query, search) do
    term = String.trim(search)

    where(
      query,
      [r],
      fragment("startsWith(?, ?)", r.commit_sha, ^String.downcase(term)) or
        fragment("startsWith(?, ?)", r.head_sha, ^String.downcase(term)) or
        fragment("positionCaseInsensitive(?, ?) > 0", r.git_branch, ^term) or
        fragment("positionCaseInsensitive(?['scheme'], ?) > 0", r.build_context, ^term) or
        fragment("positionCaseInsensitive(?['test_plan'], ?) > 0", r.build_context, ^term)
    )
  end

  @doc "An impact run of the project, by its id."
  def get_run(project_id, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Storage.get_run(project_id, id)
      _ -> {:error, :not_found}
    end
  end

  @doc """
  The impact run a test run points to: `{:ok, run}`, `{:error, :expired}`
  when it points to one past retention, or `{:error, :none}`.
  """
  def run_for_test_run(_project_id, %{test_impact_run_id: nil}), do: {:error, :none}

  def run_for_test_run(project_id, %{test_impact_run_id: id}) do
    case Storage.get_run(project_id, id) do
      {:ok, run} -> {:ok, run}
      {:error, :not_found} -> {:error, :expired}
    end
  end

  @doc """
  The diff an impact run used, or `nil` when it had no baseline, ran from a
  dirty checkout (whose diff isn't stored) or its diff expired.
  """
  def get_diff(%Run{baseline_sha: baseline}) when baseline in [nil, ""], do: nil
  def get_diff(%Run{dirty: true}), do: nil

  def get_diff(%Run{project_id: project_id, commit_sha: commit_sha, baseline_sha: baseline_sha}) do
    case Storage.get_diff(project_id, commit_sha, baseline_sha) do
      {:ok, diff} -> diff
      {:error, :not_found} -> nil
    end
  end

  @doc "The project's tracked-file globs: a change to one makes selection fall back."
  def tracked_file_globs(project), do: GitHistory.settings(project).tracked_file_globs

  @doc """
  A page of a diff's changed files, each with whether it's a tracked file
  and how many of the run's selected tests it selected. Options: `:search`
  (part of the path), `:tracked` (`true` for tracked files only), `:page`
  and `:page_size`. The files that selected the most tests come first.
  """
  def changed_files(project, %Run{} = run, diff, opts \\ []) do
    tracked = tracked_matcher(project)
    counts = selected_counts_by_path(run)
    search = opts |> Keyword.get(:search, "") |> to_string() |> String.trim() |> String.downcase()

    diff.changed_files
    |> Enum.map(fn file ->
      Map.merge(file, %{
        tracked: ExcludedPaths.excluded?(tracked, file.path),
        selected_tests_count: Map.get(counts, file.path, 0)
      })
    end)
    |> Enum.filter(
      &((search == "" or String.contains?(String.downcase(&1.path), search)) and
          (Keyword.get(opts, :tracked) != true or &1.tracked))
    )
    |> Enum.sort_by(&{-&1.selected_tests_count, &1.path})
    |> paginate_list(opts)
  end

  @doc "The diff's changed files among `paths`, keyed by path."
  def changed_files_by_path(nil, _paths), do: %{}

  def changed_files_by_path(diff, paths) do
    paths = MapSet.new(paths)
    for file <- diff.changed_files, MapSet.member?(paths, file.path), into: %{}, do: {file.path, file}
  end

  defp tracked_matcher(project) do
    project |> tracked_file_globs() |> ExcludedPaths.pattern() |> ExcludedPaths.compile()
  end

  defp selected_counts_by_path(%Run{} = run) do
    from(t in selected_query(run),
      where: t.matched_path != "",
      group_by: t.matched_path,
      select: {t.matched_path, count()}
    )
    |> ClickHouseRepo.all()
    |> Map.new(fn {path, count} -> {path, to_integer(count)} end)
  end

  @doc """
  What an impact run's tests add up to: requested, selected and skipped
  tests, the skipped tests' estimated duration from the baseline, and
  whether `test_run_id` is there to report the selected tests' results.
  """
  def run_summary(%Run{} = run, test_run_id) do
    skipped_duration =
      run
      |> skipped_queries()
      |> Enum.sum_by(fn query ->
        from(t in subquery(query), select: sum(t.duration)) |> ClickHouseRepo.one() |> to_integer()
      end)

    %{
      reported: not is_nil(test_run_id),
      requested: run.requested_count,
      selected: run.selected_count,
      skipped: run.skipped_count,
      unaffected: unaffected_count(run),
      module_skipped: module_skipped_count(run),
      skipped_modules: map_size(run.skipped_modules),
      modules: length(run.requested_modules) + map_size(run.skipped_modules),
      skip_rate: skip_rate(run),
      skipped_duration: skipped_duration
    }
  end

  @doc """
  A page of an impact run's tests, the selected ones and the skipped ones
  derived from the baseline, with their outcome in `test_run_id` (`nil`
  when it reported none for the test) and the shard they were planned on.
  Options: `:search` (part of the module, suite or test name), `:decision`
  (`selected` or `skipped`), `:reason`, `:shard`,
  `:sort_by` (`decision`, `name`, `shard` or `duration`), `:sort_order`,
  `:page` and `:page_size`.
  """
  def run_tests(%Run{} = run, test_run_id, opts \\ []) do
    plan = shard_plan(run)

    query =
      run
      |> tests_query(plan, test_run_id, opts)
      |> filter_shard(Keyword.get(opts, :shard), plan)
      |> sort_tests(Keyword.get(opts, :sort_by, "decision"), Keyword.get(opts, :sort_order, "asc"), plan)

    {rows, meta} = paginate(query, opts)
    {Enum.map(rows, &normalize_test/1), meta}
  end

  @doc "One of an impact run's tests, by its test case id, with its outcome in `test_run_id`."
  def get_run_test(%Run{} = run, test_run_id, test_case_id) do
    with {:ok, test_case_id} <- Ecto.UUID.cast(test_case_id),
         row when not is_nil(row) <-
           run
           |> tests_query(shard_plan(run), test_run_id, test_case_id: test_case_id)
           |> limit(1)
           |> ClickHouseRepo.one() do
      {:ok, normalize_test(row)}
    else
      _ -> {:error, :not_found}
    end
  end

  defp selected_query(%Run{id: id, project_id: project_id}) do
    from(t in RunTest, where: t.project_id == ^project_id and t.test_impact_run_id == ^id)
  end

  defp has_baseline?(%Run{baseline_sha: baseline}), do: baseline not in [nil, ""]

  # The baseline run's tests in `modules` (by default the requested ones),
  # with their average duration there.
  defp baseline_tests_query(%Run{project_id: project_id} = run, modules \\ nil) do
    query =
      from(c in TestCaseRun,
        where: c.project_id == ^project_id and not is_nil(c.test_case_id),
        where: c.test_run_id in subquery(baseline_test_runs(run)),
        group_by: fragment("assumeNotNull(?)", c.test_case_id),
        select: %{
          # Typed so derived rows carry the UUID string, whichever branch of a
          # union comes first.
          test_case_id: type(fragment("assumeNotNull(?)", c.test_case_id), Ecto.UUID),
          module_name: fragment("any(?)", c.module_name),
          suite_name: fragment("any(?)", c.suite_name),
          name: fragment("any(?)", c.name),
          duration: fragment("toInt64(avg(?))", c.duration)
        }
      )

    where(query, [c], c.module_name in ^(modules || run.requested_modules))
  end

  defp baseline_test_runs(%Run{project_id: project_id, baseline_sha: baseline_sha, build_context: context}) do
    query =
      from(r in CoverageRun,
        where: r.project_id == ^project_id and r.git_commit_sha == ^baseline_sha,
        select: r.test_run_id
      )

    case Map.get(context || %{}, "scheme", "") do
      "" -> query
      scheme -> where(query, [r], r.scheme == ^scheme)
    end
  end

  defp skipped_queries(run), do: for({true, branch} <- branches(run, [decision: "skipped"], [], nil), do: branch.())

  # The requested modules' baseline tests a fallback that found its baseline
  # ran, under its reason.
  defp fallback_selected_query(run, filters) do
    from(b in subquery(baseline_tests_query(run)))
    |> filter_branch(filters)
    |> select([b], %{
      test_case_id: b.test_case_id,
      module_name: b.module_name,
      suite_name: b.suite_name,
      name: b.name,
      decision: fragment("'selected'"),
      reason: fragment("?", ^run.reason),
      matched_path: fragment("?", ^run.matched_path),
      duration: b.duration
    })
  end

  # The requested modules' baseline tests coverage didn't select.
  defp unaffected_query(run, filters) do
    selected_ids = select(selected_query(run), [t], t.test_case_id)

    skipped_branch(
      from(b in subquery(baseline_tests_query(run)), where: b.test_case_id not in subquery(selected_ids)),
      filters,
      "unaffected"
    )
  end

  # The baseline tests of the modules selective testing skipped by hash.
  defp module_skipped_query(run, filters) do
    skipped_branch(
      from(b in subquery(baseline_tests_query(run, Map.keys(run.skipped_modules)))),
      filters,
      "module_skipped"
    )
  end

  defp skipped_branch(query, filters, reason) do
    query
    |> filter_branch(filters)
    |> select([b], %{
      test_case_id: b.test_case_id,
      module_name: b.module_name,
      suite_name: b.suite_name,
      name: b.name,
      decision: fragment("'skipped'"),
      reason: fragment("?", ^reason),
      matched_path: fragment("''"),
      duration: b.duration
    })
  end

  # Filters apply inside each branch of the union: ClickHouse fails to push
  # an outer filter into the skipped branch's subqueries.
  defp requested_query(run, opts) do
    reason = Keyword.get(opts, :reason)
    filters = Keyword.take(opts, [:search, :test_case_id])
    selected = selected_branch(run, if(reason in [nil, "", "any"], do: filters, else: [{:reason, reason} | filters]))

    branches = for {included?, branch} <- branches(run, opts, filters, selected), included?, do: branch.()

    case branches do
      [] -> where(selected, false)
      [first | rest] -> Enum.reduce(rest, first, &union_all(&2, ^&1))
    end
  end

  # Each branch of the union, whether the options include it, and how to
  # build it.
  defp branches(run, opts, filters, selected) do
    [
      {selected_branch?(opts) and not counted_fallback?(run), fn -> selected end},
      {counted_fallback?(run) and fallback_selected_branch?(run, opts), fn -> fallback_selected_query(run, filters) end},
      {skipped_branch?(run, opts, "unaffected") and not fallback?(run), fn -> unaffected_query(run, filters) end},
      {skipped_branch?(run, opts, "module_skipped") and run.skipped_modules != %{} and
         Keyword.get(opts, :module_skipped, true), fn -> module_skipped_query(run, filters) end}
    ]
  end

  defp selected_branch?(opts),
    do:
      Keyword.get(opts, :decision) in [nil, "", "any", "selected"] and Keyword.get(opts, :reason) not in @skipped_reasons

  # Skipped tests never ran, so they sit on no shard.
  defp fallback_selected_branch?(run, opts) do
    Keyword.get(opts, :decision) in [nil, "", "any", "selected"] and
      Keyword.get(opts, :reason) in [nil, "", "any", run.reason] and not is_integer(Keyword.get(opts, :shard))
  end

  defp skipped_branch?(run, opts, reason) do
    has_baseline?(run) and Keyword.get(opts, :decision) in [nil, "", "any", "skipped"] and
      Keyword.get(opts, :reason) in [nil, "", "any", reason] and
      not is_integer(Keyword.get(opts, :shard))
  end

  defp selected_branch(run, filters) do
    query = filter_branch(selected_query(run), filters)

    if has_baseline?(run) do
      from(t in query,
        left_join: b in subquery(baseline_tests_query(run)),
        on: b.test_case_id == t.test_case_id,
        select: %{
          test_case_id: t.test_case_id,
          module_name: t.module_name,
          suite_name: t.suite_name,
          name: t.name,
          decision: fragment("'selected'"),
          reason: fragment("toString(?)", t.reason),
          matched_path: t.matched_path,
          duration: fragment("ifNull(?, 0)", b.duration)
        }
      )
    else
      from(t in query,
        select: %{
          test_case_id: t.test_case_id,
          module_name: t.module_name,
          suite_name: t.suite_name,
          name: t.name,
          decision: fragment("'selected'"),
          reason: fragment("toString(?)", t.reason),
          matched_path: t.matched_path,
          duration: fragment("toInt64(0)")
        }
      )
    end
  end

  defp filter_branch(query, filters) do
    Enum.reduce(filters, query, fn
      {:search, search}, query -> filter_test_search(query, search)
      {:test_case_id, id}, query -> where(query, [x], x.test_case_id == ^id)
      {:reason, reason}, query -> where(query, [x], x.reason == ^reason)
    end)
  end

  defp tests_query(run, plan, test_run_id, opts) do
    from(t in subquery(requested_query(run, opts)))
    |> join_outcomes(run, test_run_id)
    |> join_shards(plan)
  end

  defp join_outcomes(query, run, test_run_id) do
    from(t in query,
      left_join: o in subquery(outcomes_query(run.project_id, test_run_id)),
      on: o.test_case_id == t.test_case_id
    )
  end

  defp join_shards(query, nil),
    do: select(query, [t, o], %{test: t, status: o.status, test_case_run_id: o.test_case_run_id, shard_index: nil})

  defp join_shards(query, plan) do
    from([t, o] in query,
      left_join: s in subquery(shard_suites_query(plan)),
      on: s.module_name == t.module_name and s.test_suite_name == t.suite_name,
      select: %{test: t, status: o.status, test_case_run_id: o.test_case_run_id, shard_index: s.shard_index}
    )
  end

  # A test's outcome in the run: failed if any of its attempts failed,
  # passed if one passed, skipped otherwise.
  defp outcomes_query(project_id, test_run_id) do
    from(c in TestCaseRun,
      where: c.project_id == ^project_id and c.test_run_id == ^test_run_id and not is_nil(c.test_case_id),
      group_by: fragment("assumeNotNull(?)", c.test_case_id),
      select: %{
        test_case_id: fragment("assumeNotNull(?)", c.test_case_id),
        status:
          fragment(
            "multiIf(countIf(? = 'failure') > 0, 'failure', countIf(? = 'success') > 0, 'success', 'skipped')",
            c.status,
            c.status
          ),
        test_case_run_id: fragment("toString(argMax(?, ?))", c.id, c.ran_at)
      }
    )
  end

  defp normalize_test(%{test: test, status: status, test_case_run_id: test_case_run_id, shard_index: shard_index}) do
    status = if status in [nil, ""], do: nil, else: status

    Map.merge(test, %{
      outcome: status,
      test_case_run_id: if(status, do: test_case_run_id),
      shard_index: if(test.decision == "selected", do: shard_index)
    })
  end

  defp filter_shard(query, shard, %ShardPlan{}) when is_integer(shard),
    do: where(query, [t, o, s], s.shard_index == ^shard)

  defp filter_shard(query, _shard, _plan), do: query

  defp sort_tests(query, "name", "desc", _plan),
    do: order_by(query, [t], desc: t.module_name, desc: t.suite_name, desc: t.name)

  defp sort_tests(query, "name", _order, _plan),
    do: order_by(query, [t], asc: t.module_name, asc: t.suite_name, asc: t.name)

  defp sort_tests(query, "duration", "asc", _plan),
    do: order_by(query, [t], asc: t.duration, asc: t.module_name, asc: t.name)

  defp sort_tests(query, "duration", _order, _plan),
    do: order_by(query, [t], desc: t.duration, asc: t.module_name, asc: t.name)

  defp sort_tests(query, "shard", order, %ShardPlan{}) do
    direction = if order == "desc", do: :desc, else: :asc
    order_by(query, [t, o, s], [{:asc, t.decision}, {^direction, s.shard_index}, {:asc, t.module_name}, {:asc, t.name}])
  end

  # Selected first: what the invocation executes is what a reader checks
  # first.
  defp sort_tests(query, _decision, "desc", _plan),
    do: order_by(query, [t], desc: t.decision, asc: t.module_name, asc: t.suite_name, asc: t.name)

  defp sort_tests(query, _decision, _order, _plan),
    do: order_by(query, [t], asc: t.decision, asc: t.module_name, asc: t.suite_name, asc: t.name)

  @doc "The latest shard plan that distributes the impact run's selected tests, or `nil`."
  def shard_plan(%Run{id: id, project_id: project_id}) do
    ClickHouseRepo.one(
      from(p in ShardPlan,
        where: p.project_id == ^project_id and p.test_impact_run_id == ^id,
        order_by: [desc: p.inserted_at],
        limit: 1
      )
    )
  end

  defp shard_suites_query(%ShardPlan{id: id, project_id: project_id}) do
    from(s in ShardPlanTestSuite,
      where: s.project_id == ^project_id and s.shard_plan_id == ^id,
      select: %{module_name: s.module_name, test_suite_name: s.test_suite_name, shard_index: s.shard_index}
    )
  end

  @doc """
  An impact run's tests per module: requested, selected and skipped, the
  skipped tests' estimated duration and why the selected ones run, most
  selected first.
  """
  def run_targets(%Run{} = run) do
    from(t in subquery(requested_query(run, module_skipped: false)),
      group_by: t.module_name,
      select: %{
        module_name: t.module_name,
        requested: count(),
        selected: fragment("countIf(? = 'selected')", t.decision),
        skipped: fragment("countIf(? = 'skipped')", t.decision),
        estimated_skipped_duration: fragment("sumIf(?, ? = 'skipped')", t.duration, t.decision),
        reasons: fragment("groupUniqArrayIf(?, ? = 'selected')", t.reason, t.decision)
      }
    )
    |> ClickHouseRepo.all()
    |> Enum.map(fn row ->
      %{
        row
        | requested: to_integer(row.requested),
          selected: to_integer(row.selected),
          skipped: to_integer(row.skipped),
          estimated_skipped_duration: to_integer(row.estimated_skipped_duration)
      }
    end)
    |> Enum.sort_by(&{-&1.selected, &1.module_name})
  end

  @doc """
  The files a test executed in its baseline, from the baseline's per-test
  coverage evidence: the paths of its `test` scope in the coverage of the
  baseline commit's test runs.
  """
  def baseline_covered_paths(project_id, baseline_sha, %{module_name: module, suite_name: suite, name: name})
      when baseline_sha not in [nil, ""] do
    scope_id = Enum.join([module, suite, name], "\u001F")

    ClickHouseRepo.all(
      from(f in CoverageFile,
        where: f.project_id == ^project_id and f.scope_kind == "test" and f.scope_id == ^scope_id,
        where:
          f.git_commit_sha == ^baseline_sha or
            f.test_run_id in subquery(
              from(r in CoverageRun,
                where: r.project_id == ^project_id and r.git_commit_sha == ^baseline_sha,
                select: r.test_run_id
              )
            ),
        distinct: true,
        select: f.path,
        order_by: f.path
      )
    )
  end

  def baseline_covered_paths(_project_id, _baseline_sha, _test), do: []

  @doc "Whether any test run of the commit reported coverage."
  def coverage?(_project_id, sha) when sha in [nil, ""], do: false

  def coverage?(project_id, sha) do
    from(r in CoverageRun,
      where: r.project_id == ^project_id and r.git_commit_sha == ^sha,
      select: 1,
      limit: 1
    )
    |> ClickHouseRepo.one()
    |> is_integer()
  end

  defp filter_test_search(query, search) when search in [nil, ""], do: query

  defp filter_test_search(query, search) do
    term = String.trim(search)

    where(
      query,
      [t],
      fragment("positionCaseInsensitive(?, ?) > 0", t.module_name, ^term) or
        fragment("positionCaseInsensitive(?, ?) > 0", t.suite_name, ^term) or
        fragment("positionCaseInsensitive(?, ?) > 0", t.name, ^term)
    )
  end

  defp paginate(query, opts) do
    page = max(Keyword.get(opts, :page, 1), 1)
    page_size = Keyword.get(opts, :page_size, 20)

    total_count =
      query
      |> exclude(:order_by)
      |> exclude(:select)
      |> select([x], count())
      |> ClickHouseRepo.one()
      |> to_integer()

    rows =
      query
      |> limit(^page_size)
      |> offset(^((page - 1) * page_size))
      |> ClickHouseRepo.all()

    {rows, %{current_page: page, total_pages: max(ceil_div(total_count, page_size), 1), total_count: total_count}}
  end

  defp paginate_list(rows, opts) do
    page = max(Keyword.get(opts, :page, 1), 1)
    page_size = Keyword.get(opts, :page_size, 20)
    total_count = length(rows)

    {Enum.slice(rows, (page - 1) * page_size, page_size),
     %{current_page: page, total_pages: max(ceil_div(total_count, page_size), 1), total_count: total_count}}
  end

  defp ceil_div(count, size), do: div(count + size - 1, size)

  defp to_integer(nil), do: 0
  defp to_integer(%Decimal{} = value), do: Decimal.to_integer(value)
  defp to_integer(value) when is_integer(value), do: value
  defp to_integer(value) when is_float(value), do: round(value)
  defp to_integer(value) when is_binary(value), do: String.to_integer(value)
end
