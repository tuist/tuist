defmodule Tuist.Tests.RunSelections do
  @moduledoc """
  Test selection effectiveness: how many of the tests in a test run's scope
  its selection avoided, stored per run in `test_run_selections`
  (`Tuist.Tests.RunSelection`), for the dashboards to read as a pooled
  ratio, avoided tests over tests in scope summed across runs. They don't
  read it yet: the table is filled for past runs first.

  Only selection counts as avoided: the tests in the modules Tuist's
  selective testing skipped by hash (`module_hash`) and the tests
  coverage-based test selection skipped (`coverage`). Tests a run skipped
  on its own (`XCTSkip`, `@Ignore`, quarantine) are outside both numbers:
  a run's executed tests are its test cases that didn't report `skipped`,
  and the avoided ones come from the selection, never from a skipped status.
  The scope is the executed tests plus the avoided ones.

  How a run's avoided tests are counted, Xcode being the only build system
  that selects today:

  - A run whose impact run (`Tuist.TestImpactAnalysis.Run`) confirmed a
    baseline takes its `skipped_count`: the tests coverage skipped, and the
    baseline's tests in the modules hashing skipped, which are estimated.
  - Any other run with selective testing data (its command event hashed test
    targets, or an impact run without a baseline) counts the tests of each
    module hashing skipped. Hashing only skips a module whose hash a run
    stored after passing it, so the module's tests are counted in the run
    that stored the hash: among the module's 20 latest earlier executions
    (test command events that ran it), the latest whose `xcode_targets` row
    missed with the same hash, as long as its run executed tests of the module
    and didn't narrow it with its identifiers. That count is exact. Without
    one (`--no-upload`, results never uploaded, an older execution, or past
    the 30 days `xcode_targets` keeps), the module's latest earlier execution
    gives the count, which is estimated. A module with no execution in the
    last three years counts no test.

  Every read is by a sorting key (`command_events` by project, test cases by
  test run) and bounded by `@query_settings`: scanning `test_case_runs` by
  module, or `xcode_targets` for a hash, reads too much for the projects that
  test the most.

  A run narrowed with `only_test_identifiers` counts only the skipped modules
  it named whole. Several shards can share one impact run; reads count its
  avoided tests once (`test_impact_run_id`).

  Rows are recorded a few seconds after a run's command event or test run
  arrives (`Tuist.Tests.Workers.RecordRunSelectionWorker`), and recomputed
  whenever either arrives again: the latest computation wins. Older runs are
  filled by `backfill/3`.
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.CommandEvents.Event
  alias Tuist.Environment
  alias Tuist.IngestRepo
  alias Tuist.TestImpactAnalysis.Run, as: ImpactRun
  alias Tuist.Tests.RunSelection
  alias Tuist.Tests.Test
  alias Tuist.Tests.TestCase
  alias Tuist.Tests.TestCaseRunByTestRun
  alias Tuist.Tests.Workers.RecordRunSelectionWorker
  alias Tuist.Xcode.XcodeTarget

  # How far back a skipped module's earlier executions are looked for, the
  # narrowest first: a module that runs often is found in the first window.
  @history_windows_days [7, 31, 90, 1095]
  # `xcode_targets` keeps its rows 30 days, so no earlier hash is found past it.
  @hash_window_days 31
  # How many earlier executions of a skipped module a hit looks among, also
  # written in `latest_executions/5`.
  @executions_per_hit 20
  # Bounds every read the counting makes, so recording and backfilling share
  # ClickHouse with the dashboards' queries rather than competing with them.
  # They keep `ClickHouseRepo`'s time limit, which ends a read before the
  # client stops waiting for it.
  @query_settings [max_threads: 2, max_memory_usage: 1_073_741_824]
  @chunk_size 1_000
  # `xcode_targets` is read by event through a projection; past a few hundred
  # events ClickHouse reads it in far larger ranges.
  @event_chunk_size 200
  @backfill_page_size 200
  @backfill_budget_ms to_timeout(minute: 5)

  # The reasons an avoided test is counted under.
  @module_hash "module_hash"
  @coverage "coverage"

  ## Recording

  @doc """
  Queues the computation of a test run's row, once its command event,
  targets and test cases are flushed.
  """
  def enqueue(project_id, test_run_id) do
    delay = div(Environment.clickhouse_flush_interval_ms(), 1000) + 5

    %{project_id: project_id, test_run_id: test_run_id}
    |> RecordRunSelectionWorker.new(schedule_in: delay)
    |> Oban.insert()
  end

  @doc """
  Records one test run's row. `:not_found` while the run isn't stored, and
  `{:pending, seconds}` while its test cases may still be in a buffer.
  """
  def record_run(project_id, test_run_id) do
    settle_ms = Environment.clickhouse_flush_interval_ms() + 5_000

    case project_id |> load_runs([test_run_id]) |> Map.get(test_run_id) do
      nil ->
        :not_found

      run ->
        age_ms = NaiveDateTime.diff(NaiveDateTime.utc_now(), run.inserted_at, :millisecond)

        if age_ms < settle_ms do
          {:pending, div(settle_ms - age_ms, 1000) + 1}
        else
          record(project_id, [test_run_id])
          :ok
        end
    end
  end

  @doc """
  Computes and stores the rows of the given test runs of a project, replacing
  earlier ones. Runs without selection data get no row. Returns the number of
  rows written.
  """
  def record(_project_id, []), do: 0

  def record(project_id, test_run_ids) do
    rows = rows(project_id, Enum.uniq(test_run_ids))
    rows |> Enum.chunk_every(@chunk_size) |> Enum.each(&IngestRepo.insert_all(RunSelection, &1))
    length(rows)
  end

  defp rows(project_id, test_run_ids) do
    runs = load_runs(project_id, test_run_ids)
    events = load_events(project_id, Map.keys(runs))
    impact_runs = load_impact_runs(project_id, runs |> Map.values() |> Enum.map(& &1.test_impact_run_id))
    executed = executed_counts(project_id, Map.keys(runs))

    {coverage, hashed} =
      runs
      |> Map.values()
      |> Enum.map(&{&1, Map.get(impact_runs, &1.test_impact_run_id), Map.get(events, &1.id)})
      |> Enum.reject(fn {_run, impact, event} -> is_nil(impact) and (is_nil(event) or event.test_targets == []) end)
      |> Enum.split_with(fn {_run, impact, _event} -> impact != nil and has_baseline?(impact) end)

    hits = hits(project_id, hashed)
    counts = hit_counts(project_id, hits)
    now = NaiveDateTime.utc_now()

    coverage_rows =
      Enum.map(coverage, fn {run, impact, _event} ->
        by_hash = impact.skipped_modules |> Map.values() |> Enum.sum() |> min(impact.skipped_count)
        avoided_by = %{@module_hash => by_hash, @coverage => impact.skipped_count - by_hash}
        row(run, impact.strategy, executed, avoided_by, by_hash, now)
      end)

    hashed_rows =
      Enum.map(hashed, fn {run, impact, _event} ->
        run_counts = hits |> Enum.filter(&(&1.run.id == run.id)) |> Enum.map(&Map.get(counts, {run.id, &1.module}))
        avoided = run_counts |> Enum.map(&elem(&1, 0)) |> Enum.sum()
        estimated = for {tests, :estimated} <- run_counts, reduce: 0, do: (sum -> sum + tests)
        strategy = if impact, do: impact.strategy, else: @module_hash
        row(run, strategy, executed, %{@module_hash => avoided}, estimated, now)
      end)

    coverage_rows ++ hashed_rows
  end

  defp row(run, strategy, executed, avoided_by, estimated, now) do
    avoided_by = avoided_by |> Enum.reject(fn {_reason, tests} -> tests == 0 end) |> Map.new()
    avoided = avoided_by |> Map.values() |> Enum.sum()

    %{
      project_id: run.project_id,
      test_run_id: run.id,
      ran_at: usec(run.ran_at),
      build_system: run.build_system || "",
      is_ci: run.is_ci || false,
      scheme: run.scheme || "",
      git_branch: run.git_branch || "",
      strategy: strategy,
      test_impact_run_id: run.test_impact_run_id,
      scope_tests: Map.get(executed, run.id, 0) + avoided,
      avoided_tests: avoided,
      estimated_tests: estimated,
      avoided_by: avoided_by,
      inserted_at: now
    }
  end

  defp usec(%NaiveDateTime{microsecond: {microsecond, _precision}} = datetime),
    do: %{datetime | microsecond: {microsecond, 6}}

  defp has_baseline?(%ImpactRun{baseline_sha: sha}), do: sha not in [nil, ""]

  # The modules each run's selection skipped by hash, with the hash its
  # command event reported for each: the event's hit lists, or the impact
  # run's skipped modules when no event arrived.
  defp hits(project_id, hashed) do
    hashes =
      hashed
      |> Enum.flat_map(fn {_run, _impact, event} -> if event, do: event.ids, else: [] end)
      |> then(&target_hashes(project_id, &1, hashed))

    Enum.flat_map(hashed, fn {run, impact, event} ->
      modules =
        cond do
          event -> event.hits
          impact -> Map.keys(impact.skipped_modules)
        end

      modules
      |> Enum.uniq()
      |> Enum.filter(&in_scope?(run, &1))
      |> Enum.map(&%{run: run, module: &1, hash: Map.get(hashes, {run.id, &1})})
    end)
  end

  # A run narrowed to some tests only avoided the skipped modules it named
  # whole: the others weren't in its scope.
  defp in_scope?(%{only_test_identifiers: only}, _module) when only in [nil, []], do: true
  defp in_scope?(%{only_test_identifiers: only}, module), do: module in only

  # `%{{test_run_id, target} => hash}` for the hashed targets of the events.
  defp target_hashes(_project_id, [], _hashed), do: %{}

  defp target_hashes(project_id, event_ids, hashed) do
    run_of_event =
      for {run, _impact, event} <- hashed, event != nil, id <- event.ids, into: %{}, do: {id, run}

    ran_ats = Enum.map(hashed, fn {run, _impact, _event} -> run.ran_at end)
    since = ran_ats |> Enum.min(NaiveDateTime) |> days_before(2)
    until = ran_ats |> Enum.max(NaiveDateTime) |> days_after(2)

    event_ids
    |> Enum.chunk_every(@event_chunk_size)
    |> Enum.flat_map(fn ids ->
      ClickHouseRepo.all(
        from(t in XcodeTarget,
          where: t.command_event_id in ^ids and t.project_id == ^project_id,
          where: t.inserted_at >= ^since and t.inserted_at < ^until,
          where: not is_nil(t.selective_testing_hash),
          distinct: true,
          select: {t.command_event_id, t.name, t.selective_testing_hash}
        ),
        settings: @query_settings
      )
    end)
    |> Map.new(fn {event_id, name, hash} -> {{run_of_event[event_id].id, name}, hash} end)
  end

  # `%{{test_run_id, module} => {tests, :exact | :estimated}}` for every hit.
  # A hit is counted in an earlier execution of its module: exactly in the
  # latest one whose target missed with the hit's hash, otherwise in the
  # latest one, an estimate. Executions are looked for in wider windows until
  # found; a hash only within the days `xcode_targets` keeps them.
  defp hit_counts(_project_id, []), do: %{}

  defp hit_counts(project_id, hits) do
    history = %{executions: %{}, candidates: %{}, tests: %{}, hashes: %{}, days: 0}
    {counts, unknown} = resolve_hits(project_id, hits, @history_windows_days, history, %{}, %{})

    unknown
    |> Map.new(&{hit_key(&1), {0, :estimated}})
    |> Map.merge(counts)
  end

  defp resolve_hits(_project_id, [], _windows, _history, resolved, _fallbacks), do: {resolved, []}
  defp resolve_hits(_project_id, hits, [], _history, resolved, _fallbacks), do: {resolved, hits}

  defp resolve_hits(project_id, hits, [days | windows], history, resolved, fallbacks) do
    history = earlier_executions(project_id, hits, days, history)

    {resolved, fallbacks, unresolved} =
      Enum.reduce(hits, {resolved, fallbacks, []}, fn hit, {resolved, fallbacks, unresolved} ->
        key = hit_key(hit)
        sources = sources(history, hit, days)
        exact = hit.hash && Enum.find(sources, &(&1.hash == hit.hash))
        estimate = with %{tests: tests} <- List.first(sources), do: {tests, :estimated}

        cond do
          exact ->
            {Map.put(resolved, key, {exact.tests, :exact}), fallbacks, unresolved}

          hit.hash && days < @hash_window_days ->
            fallbacks = if estimate, do: Map.put_new(fallbacks, key, estimate), else: fallbacks
            {resolved, fallbacks, [hit | unresolved]}

          estimate = estimate || Map.get(fallbacks, key) ->
            {Map.put(resolved, key, estimate), fallbacks, unresolved}

          true ->
            {resolved, fallbacks, [hit | unresolved]}
        end
      end)

    resolve_hits(project_id, unresolved, windows, history, resolved, fallbacks)
  end

  defp hit_key(hit), do: {hit.run.id, hit.module}

  # `[%{tests, hash}]`, newest first: the hit's candidates that executed tests
  # of the module without narrowing it, other than its own run's.
  defp sources(history, hit, days) do
    for execution <- Map.fetch!(history.candidates, hit_key(hit)),
        execution.run_id != hit.run.id,
        tests = Map.get(history.tests, {execution.run_id, hit.module}) do
      hash = if days <= @hash_window_days, do: Map.get(history.hashes, {execution.event_id, hit.module})
      %{tests: tests, hash: hash}
    end
  end

  # Sets each hit's candidates for the window, its module's 20 latest
  # executions within `days` before its run, and reads their tests and,
  # within the days `xcode_targets` keeps, their hashes. What earlier windows
  # read is kept: a hit that already had 20 candidates has the same ones in a
  # wider window, and the others only need the days this window adds, so the
  # wide windows read the few modules that rarely run rather than every event
  # in them.
  defp earlier_executions(project_id, hits, days, history) do
    open = Enum.reject(hits, &(length(Map.get(history.candidates, hit_key(&1), [])) == @executions_per_hit))
    executions = read_executions(project_id, open, days, history)

    candidates =
      Map.new(hits, fn hit ->
        since = days_before(hit.run.ran_at, days)

        latest =
          executions
          |> Map.get(hit.module, [])
          |> Enum.filter(
            &(not NaiveDateTime.before?(&1.ran_at, since) and NaiveDateTime.before?(&1.ran_at, hit.run.ran_at))
          )
          |> Enum.sort_by(&{&1.order, &1.event_id, &1.run_id})
          |> Enum.take(@executions_per_hit)

        {hit_key(hit), latest}
      end)

    module_executions =
      Enum.uniq(for hit <- hits, execution <- candidates[hit_key(hit)], do: Map.put(execution, :module, hit.module))

    pairs =
      module_executions
      |> Enum.map(&{&1.run_id, &1.module})
      |> Enum.uniq()
      |> Enum.reject(&Map.has_key?(history.tests, &1))

    tests = pairs |> Map.new(&{&1, nil}) |> Map.merge(module_tests(project_id, pairs)) |> Map.merge(history.tests)
    hashes = candidate_hashes(project_id, hits, module_executions, tests, days, history.hashes)

    %{history | executions: executions, candidates: candidates, tests: tests, hashes: hashes, days: days}
  end

  # Adds to the executions read so far, by module, those the open hits need:
  # within `days` before their runs and older than the previous window, which
  # was read whole for them.
  defp read_executions(_project_id, [], _days, history), do: history.executions

  defp read_executions(project_id, open, days, history) do
    ran_ats = Enum.map(open, & &1.run.ran_at)
    since = ran_ats |> Enum.min(NaiveDateTime) |> days_before(days)
    until = ran_ats |> Enum.max(NaiveDateTime) |> days_before(history.days)
    modules = open |> Enum.map(& &1.module) |> Enum.uniq()
    run_times = ran_ats |> Enum.uniq() |> Enum.map(&usec/1)

    project_id
    |> latest_executions(modules, run_times, since, until)
    |> Enum.group_by(& &1.module, &Map.delete(&1, :module))
    |> Enum.reduce(history.executions, fn {module, found}, executions ->
      Map.update(executions, module, found, &Enum.uniq(&1 ++ found))
    end)
  end

  # `%{{command_event_id, module} => hash | nil}` with the candidates that
  # count tests of a module a hit hashed, looked up once each.
  defp candidate_hashes(project_id, hits, module_executions, tests, days, hashes) do
    hashed_modules = for hit <- hits, hit.hash, into: MapSet.new(), do: hit.module

    pending =
      Enum.filter(module_executions, fn execution ->
        MapSet.member?(hashed_modules, execution.module) and Map.get(tests, {execution.run_id, execution.module}) != nil and
          not Map.has_key?(hashes, {execution.event_id, execution.module})
      end)

    if days <= @hash_window_days and pending != [] do
      ran_ats = Enum.map(module_executions, & &1.ran_at)
      since = ran_ats |> Enum.min(NaiveDateTime) |> days_before(1)
      until = ran_ats |> Enum.max(NaiveDateTime) |> days_after(1)

      pending
      |> Map.new(&{{&1.event_id, &1.module}, nil})
      |> Map.merge(execution_hashes(project_id, pending, since, until))
      |> Map.merge(hashes)
    else
      hashes
    end
  end

  # The latest test command events in `[since, until)` that executed each of
  # the modules, at most 20 per module between consecutive run times: the
  # event's test targets less the ones it hit. Every run's 20 latest
  # executions before it are among those of the gaps below it. Read from
  # `command_events`, whose sorting key starts with the project and event
  # name, so it stays a narrow scan. The hits are taken out with
  # `arrayExcept`, not a lambda: a lambda that reads the hit columns copies
  # them for every test target, which runs past the memory limit on events
  # with hundreds of targets.
  defp latest_executions(project_id, modules, run_times, since, until) do
    executions =
      from(e in test_events(project_id),
        where: e.ran_at >= ^since and e.ran_at < ^until and not is_nil(e.test_run_id),
        where: fragment("hasAny(?, ?)", e.test_targets, type(^modules, {:array, :string})),
        select: %{
          module:
            fragment(
              "arrayJoin(arrayExcept(arrayIntersect(?, ?), arrayConcat(?, ?)))",
              e.test_targets,
              type(^modules, {:array, :string}),
              e.local_test_target_hits,
              e.remote_test_target_hits
            ),
          ran_at: e.ran_at,
          event_id: e.id,
          run_id: e.test_run_id
        }
      )

    from(x in subquery(executions),
      group_by: [x.module, fragment("arrayCount(t -> t <= ?, ?)", x.ran_at, ^run_times)],
      select:
        {x.module,
         fragment(
           "groupArraySorted(20)((-toUnixTimestamp64Micro(?), toString(?), toString(assumeNotNull(?)), ?))",
           x.ran_at,
           x.event_id,
           x.run_id,
           x.ran_at
         )}
    )
    |> ClickHouseRepo.all(settings: @query_settings)
    |> Enum.flat_map(fn {module, executions} ->
      for {order, event_id, run_id, ran_at} <- executions,
          do: %{module: module, order: order, event_id: event_id, run_id: run_id, ran_at: ran_at}
    end)
  end

  # `%{{test_run_id, module} => tests}`: the distinct tests each run executed
  # of the module, read by test run, the sorting key of
  # `test_case_runs_by_test_run`. Runs that executed none, or narrowed the
  # module with their identifiers, are left out.
  defp module_tests(_project_id, []), do: %{}

  defp module_tests(project_id, pairs) do
    modules = pairs |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
    wanted = MapSet.new(pairs)

    test_cases =
      from(c in TestCase,
        where: c.project_id == ^project_id and c.module_name in ^modules,
        distinct: true,
        select: %{id: c.id, module: c.module_name}
      )

    pairs
    |> Enum.map(&elem(&1, 0))
    |> Enum.uniq()
    |> Enum.chunk_every(@chunk_size)
    |> Enum.flat_map(fn ids ->
      ClickHouseRepo.all(
        from(r in TestCaseRunByTestRun,
          join: c in subquery(test_cases),
          on: r.test_case_id == c.id,
          where: r.test_run_id in ^ids and r.project_id == ^project_id,
          where: fragment("? != 'skipped'", r.status),
          group_by: [r.test_run_id, c.module],
          select: %{run_id: r.test_run_id, module: c.module, tests: fragment("toUInt32(uniqExact(?))", r.test_case_id)}
        ),
        settings: @query_settings
      )
    end)
    |> Enum.filter(&(&1.tests > 0 and MapSet.member?(wanted, {&1.run_id, &1.module})))
    |> unnarrowed(project_id)
    |> Map.new(&{{&1.run_id, &1.module}, &1.tests})
  end

  # `%{{command_event_id, module} => hash}` for the executions whose target
  # missed with a hash. `xcode_targets` isn't sorted by project, so the read is
  # bounded to the days around the executions. The modules are matched with
  # `indexOf` rather than `IN`: ClickHouse checks an `IN` list against the
  # name's n-gram skip indexes granule by granule, which takes longer than the
  # read itself with hundreds of modules.
  defp execution_hashes(project_id, executions, since, until) do
    modules = executions |> Enum.map(& &1.module) |> Enum.uniq()

    executions
    |> Enum.map(& &1.event_id)
    |> Enum.uniq()
    |> Enum.chunk_every(@event_chunk_size)
    |> Enum.flat_map(fn ids ->
      ClickHouseRepo.all(
        from(t in XcodeTarget,
          where: t.command_event_id in ^ids and t.project_id == ^project_id,
          where: t.inserted_at >= ^since and t.inserted_at < ^until,
          where: fragment("indexOf(?, ?) > 0", type(^modules, {:array, :string}), t.name),
          where: not is_nil(t.selective_testing_hash),
          where: fragment("? = 'miss'", t.selective_testing_hit),
          distinct: true,
          select: {t.command_event_id, t.name, t.selective_testing_hash}
        ),
        settings: @query_settings
      )
    end)
    |> Map.new(fn {event_id, name, hash} -> {{event_id, name}, hash} end)
  end

  # Drops the module runs whose run narrowed the module: its only identifiers
  # name part of it, or its skip identifiers name any of it.
  defp unnarrowed([], _project_id), do: []

  defp unnarrowed(module_runs, project_id) do
    runs = load_runs(project_id, module_runs |> Enum.map(& &1.run_id) |> Enum.uniq())

    Enum.reject(module_runs, fn %{run_id: run_id, module: module} ->
      case Map.get(runs, run_id) do
        nil -> true
        run -> narrowed?(run, module)
      end
    end)
  end

  defp narrowed?(run, module) do
    prefix = module <> "/"

    Enum.any?(run.only_test_identifiers || [], &String.starts_with?(&1, prefix)) or
      Enum.any?(run.skip_test_identifiers || [], &(&1 == module or String.starts_with?(&1, prefix)))
  end

  # `%{test_run_id => executed tests}`: the distinct test cases each run
  # reported with a status other than skipped.
  defp executed_counts(_project_id, []), do: %{}

  defp executed_counts(project_id, run_ids) do
    run_ids
    |> Enum.chunk_every(@chunk_size)
    |> Enum.flat_map(fn ids ->
      ClickHouseRepo.all(
        from(r in TestCaseRunByTestRun,
          where: r.test_run_id in ^ids and r.project_id == ^project_id,
          where: fragment("? != 'skipped'", r.status),
          group_by: r.test_run_id,
          select: {r.test_run_id, fragment("toUInt32(uniqExact(ifNull(toString(?), ?)))", r.test_case_id, r.name)}
        )
      )
    end)
    |> Map.new()
  end

  defp load_runs(_project_id, []), do: %{}

  defp load_runs(project_id, run_ids) do
    run_ids
    |> Enum.chunk_every(@chunk_size)
    |> Enum.flat_map(fn ids ->
      ClickHouseRepo.all(
        from(t in Test.query(),
          where: t.project_id == ^project_id and t.id in ^ids,
          select: %{
            id: t.id,
            project_id: t.project_id,
            ran_at: t.ran_at,
            inserted_at: t.inserted_at,
            build_system: t.build_system,
            is_ci: t.is_ci,
            scheme: t.scheme,
            git_branch: t.git_branch,
            test_impact_run_id: t.test_impact_run_id,
            only_test_identifiers: t.only_test_identifiers,
            skip_test_identifiers: t.skip_test_identifiers
          }
        )
      )
    end)
    |> Map.new(&{&1.id, &1})
  end

  # `%{test_run_id => %{ids, test_targets, hits}}`: the test command events
  # each run reported, merged, as a sharded run's shards each send one.
  defp load_events(_project_id, []), do: %{}

  defp load_events(project_id, run_ids) do
    run_ids
    |> Enum.chunk_every(@chunk_size)
    |> Enum.flat_map(fn ids ->
      ClickHouseRepo.all(
        from(e in test_events(project_id),
          where: e.test_run_id in ^ids,
          select: {e.test_run_id, e.id, e.test_targets, e.local_test_target_hits, e.remote_test_target_hits}
        )
      )
    end)
    |> Enum.group_by(&elem(&1, 0))
    |> Map.new(fn {run_id, events} ->
      {run_id,
       %{
         ids: Enum.map(events, &elem(&1, 1)),
         test_targets: events |> Enum.flat_map(&elem(&1, 2)) |> Enum.uniq(),
         hits: events |> Enum.flat_map(&(elem(&1, 3) ++ elem(&1, 4))) |> Enum.uniq()
       }}
    end)
  end

  defp load_impact_runs(project_id, ids) do
    case ids |> Enum.reject(&is_nil/1) |> Enum.uniq() do
      [] ->
        %{}

      ids ->
        from(r in ImpactRun, where: r.project_id == ^project_id and r.id in ^ids)
        |> ClickHouseRepo.all()
        |> Map.new(&{&1.id, &1})
    end
  end

  defp test_events(project_id) do
    from(e in Event,
      where: e.project_id == ^project_id,
      where:
        e.name == "test" or
          (e.name == "xcodebuild" and (e.subcommand == "test" or e.subcommand == "test-without-building"))
    )
  end

  defp days_before(datetime, days), do: NaiveDateTime.add(datetime, -days * 86_400, :second)
  defp days_after(datetime, days), do: NaiveDateTime.add(datetime, days * 86_400, :second)

  ## Backfill

  @doc """
  The projects with runs to backfill: those whose test command events hashed
  test targets for a test run, and those whose test runs point to an impact
  run.
  """
  def backfill_project_ids do
    from_events =
      ClickHouseRepo.all(
        from(e in Event,
          where: e.name in ["test", "xcodebuild"] and not is_nil(e.test_run_id) and e.test_targets_count > 0,
          distinct: true,
          select: e.project_id
        )
      )

    from_impact_runs =
      ClickHouseRepo.all(from(t in Test, where: not is_nil(t.test_impact_run_id), distinct: true, select: t.project_id))

    Enum.uniq(from_events ++ from_impact_runs)
  end

  @doc """
  Records the rows of a project's earlier runs, newest first, a page of runs
  at a time for a few minutes. Returns `:done`, or `{:continue, cursor}` to
  pass back to carry on where it stopped. The runs come from the test command
  events that hashed test targets, then from the test runs that point to an
  impact run; a run in both is recorded twice, to the same row. Options
  `:since` and `:before` limit it to the runs from or before a time.
  """
  def backfill(project_id, cursor \\ nil, opts \\ []) do
    deadline = System.monotonic_time(:millisecond) + @backfill_budget_ms
    backfill_pages(project_id, cursor || %{"phase" => "events"}, opts, deadline)
  end

  defp backfill_pages(project_id, cursor, opts, deadline) do
    if System.monotonic_time(:millisecond) > deadline do
      {:continue, cursor}
    else
      case backfill_page(project_id, cursor, opts) do
        {[], %{"phase" => "events"}} ->
          backfill_pages(project_id, %{"phase" => "impact_runs"}, opts, deadline)

        {[], _cursor} ->
          :done

        {run_ids, next} ->
          record(project_id, run_ids)
          backfill_pages(project_id, next, opts, deadline)
      end
    end
  end

  defp backfill_page(project_id, %{"phase" => "events"} = cursor, opts) do
    page =
      from(e in test_events(project_id),
        where: not is_nil(e.test_run_id) and e.test_targets_count > 0,
        order_by: [desc: e.ran_at, desc: e.id],
        limit: @backfill_page_size,
        select: {e.ran_at, e.id, e.test_run_id}
      )
      |> within(opts)
      |> after_cursor(cursor)
      |> ClickHouseRepo.all(settings: @query_settings)

    page_result(page, "events")
  end

  defp backfill_page(project_id, %{"phase" => "impact_runs"} = cursor, opts) do
    page =
      from(t in Test.query(),
        where: t.project_id == ^project_id and not is_nil(t.test_impact_run_id),
        order_by: [desc: t.ran_at, desc: t.id],
        limit: @backfill_page_size,
        select: {t.ran_at, t.id, t.id}
      )
      |> within(opts)
      |> after_cursor(cursor)
      |> ClickHouseRepo.all(settings: @query_settings)

    page_result(page, "impact_runs")
  end

  defp within(query, opts) do
    query =
      case Keyword.get(opts, :since) do
        nil -> query
        since -> where(query, [x], x.ran_at >= ^since)
      end

    case Keyword.get(opts, :before) do
      nil -> query
      before -> where(query, [x], x.ran_at < ^before)
    end
  end

  defp after_cursor(query, %{"ran_at" => ran_at, "id" => id}) do
    ran_at = NaiveDateTime.from_iso8601!(ran_at)
    where(query, [x], fragment("(?, toString(?)) < (?, ?)", x.ran_at, x.id, ^ran_at, ^id))
  end

  defp after_cursor(query, _cursor), do: query

  defp page_result([], phase), do: {[], %{"phase" => phase}}

  defp page_result(page, phase) do
    {ran_at, id, _run_id} = List.last(page)
    {Enum.map(page, &elem(&1, 2)), %{"phase" => phase, "ran_at" => NaiveDateTime.to_iso8601(ran_at), "id" => id}}
  end
end
