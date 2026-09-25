defmodule Tuist.Tests.Coverage.Reported do
  @moduledoc """
  A commit's **reported** coverage: what its runs observed plus the coverage
  carried forward for the tests they skipped.

  A selective run measures less than the commit is covered by: the tests it
  skipped would have covered lines too. The run's client lists every
  candidate test (`Tuist.Tests.Enumeration`), so the skipped ones are known,
  and per-test evidence (`Tuist.Tests.Coverage.Evidence`) says which lines
  each of them ran the last time it executed. Where the run could not list
  them, because selective testing skipped a whole scheme or a test target a
  generated project then left out of the workspace (the command event names
  it as a hit), the candidates come from the nearest ancestor run that did.
  That coverage is carried forward only when it provably still applies:

  - the evidence comes from an ancestor of the commit, from a run on a clean
    checkout, and the nearest such ancestor wins;
  - the test passed in that run;
  - every file the test executed there, and every file its suite's setup
    executed, has the same blob at the commit, and so does every tracked file
    of the project;
  - the evidence holds lines, not only files, for every file that counts.

  A test target selective testing skipped carries whole, from the evidence
  of the target's own process, when the source run hashed the target the
  same way the commit's run did: the same inputs, so the same tests over the
  same code. The guards above apply to it as to a test. It needs no observer
  scope per test, so it covers Swift Testing without the attribution trait
  and tests that ran in parallel.

  A skipped test that fails any of these is a **gap**: nothing is carried for
  it and the figure is a lower bound, which `kind` says (`partial`). Files an
  ancestor measured that no run at the commit compiled keep their executable
  lines when their blob is unchanged, so a run that built half the project is
  compared over the whole of it; one whose blob changed is a gap too.

  Carried coverage always chains back to a run in which the test really
  executed: evidence rows exist only where tests ran, so an estimate is never
  carried from an estimate.
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.CommandEvents.Event
  alias Tuist.GitHistory
  alias Tuist.KeyValueStore
  alias Tuist.Projects.Project
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.Evidence
  alias Tuist.Tests.Coverage.ExcludedPaths
  alias Tuist.Tests.CoverageFile
  alias Tuist.Tests.EnumeratedTest
  alias Tuist.Tests.Test
  alias Tuist.Tests.TestCaseRun
  alias Tuist.Xcode.XcodeTarget

  # A lookup scoped to runs binds every run id as a query parameter too, so the
  # run ids are chunked first and each chunk is kept small enough that the ids
  # it is crossed with still have room. See `Coverage.id_chunks/2`.
  @run_id_chunk 200

  @cache_ttl to_timeout(minute: 5)

  # How many of a scheme's nearest ancestor runs a skipped target's candidates
  # are looked for in. The nearest one practically always lists it: a target
  # is only skipped because a run that built it passed.
  @module_source_runs 20

  @doc """
  The commit's reported coverage, or nil when no run measured it.

  `kind` is `measured` when the runs skipped nothing, `reported` when every
  skipped test was carried and no file is left out, `partial` when gaps
  remain, and `observed` when the runs' clients listed no candidates, so what
  was skipped cannot be told and the figure is the observed one.
  """
  def compute(%Project{} = project, sha, opts \\ []) do
    runs = Keyword.get_lazy(opts, :runs, fn -> Commits.runs(project.id, sha) end)
    unmeasured = if runs == [], do: unmeasured_runs(project.id, sha), else: []

    if runs == [] and unmeasured == [] do
      nil
    else
      excluded = Keyword.get_lazy(opts, :excluded, fn -> ExcludedPaths.pattern_for_project(project) end)
      run_ids = Enum.map(runs, & &1.test_run_id)
      observed = observed_files(project.id, run_ids, excluded)

      repository_id =
        case runs do
          [] -> unmeasured |> Enum.map(& &1.git_repository_id) |> Enum.max()
          _ -> runs |> Enum.map(& &1.git_repository_id) |> Enum.max()
        end

      schemes = runs |> Enum.map(& &1.scheme) |> Enum.uniq()
      # Where a run measured nothing its scheme still says what the commit set
      # out to cover, which is what an ancestor's files are read back over.
      covered_schemes = (schemes ++ Enum.map(unmeasured, & &1.scheme)) |> Enum.reject(&(&1 in [nil, ""])) |> Enum.uniq()

      hits = selective_testing_hits(project.id, repository_id, run_ids)

      case skipped_tests(project, repository_id, sha, {run_ids, hits}, schemes) do
        {:not_enumerated, _ancestry} ->
          result(observed, "observed", [], [], 0, [])

        {[], _ancestry} ->
          result(observed, "measured", [], [], 0, [])

        {skipped, ancestry} ->
          context = %{repository_id: repository_id, sha: sha, ancestry: ancestry}
          carry(project, context, {run_ids, hits, covered_schemes}, observed, skipped, excluded)
      end
    end
  end

  @doc """
  The repository the commit's runs reported, and the build system they used,
  for a commit no run measured. Nil and `""` when it has no clean run.
  """
  def repository_id(project_id, sha) do
    project_id |> unmeasured_runs(sha) |> Enum.map(& &1.git_repository_id) |> Enum.max(fn -> nil end)
  end

  def build_system(project_id, sha) do
    case unmeasured_runs(project_id, sha) do
      [run | _] -> run.build_system
      [] -> ""
    end
  end

  # The commit's runs from a clean checkout, whether or not they measured
  # anything. A commit every scheme was skipped whole on has only these: no
  # coverage to fold, but proof that the test job ran, which is what separates
  # it from a pipeline that died before reaching the tests and must not have a
  # baseline carried into it.
  defp unmeasured_runs(project_id, sha) do
    ClickHouseRepo.all(
      from(t in Test,
        where: t.project_id == ^project_id and t.git_commit_sha == ^sha and t.git_dirty == false,
        group_by: t.id,
        select: %{
          test_run_id: t.id,
          scheme: fragment("any(?)", t.scheme),
          build_system: fragment("any(?)", t.build_system),
          git_repository_id: fragment("argMax(?, ?)", t.git_repository_id, t.inserted_at)
        }
      ),
      settings: [select_sequential_consistency: 1]
    )
  end

  defp carry(project, %{repository_id: repository_id, sha: sha, ancestry: ancestry}, runs, observed, skipped, excluded) do
    {run_ids, hits, schemes} = runs

    context = %{
      project: project,
      repository_id: repository_id,
      sha: sha,
      ancestry: ancestry,
      run_ids: run_ids,
      hits: hits,
      observed: observed,
      blobs: run_blobs(project.id, run_ids),
      excluded: ExcludedPaths.compile(excluded)
    }

    {carried_tests, carried_lines, sources} = carried(context, skipped)

    {files, gap_files} =
      observed
      |> add_carried_lines(context, run_ids, carried_lines, sources)
      |> add_unbuilt_files(context, schemes)

    kind = if length(carried_tests) == length(skipped) and gap_files == 0, do: "reported", else: "partial"
    shas = sources |> Map.values() |> Enum.map(& &1.sha) |> Enum.uniq() |> Enum.sort()
    files |> result(kind, skipped, carried_tests, gap_files, shas) |> Map.put(:carried_lines, carried_lines)
  end

  # What the pages read (`merged_files/4`, `file/4`) is the reported coverage
  # the commit's published version settled, cached against that version: on a
  # suite of thousands a compute costs about a second and a page reads it more
  # than once. The settings that change the answer without a new version are
  # part of the key. Unlocked: a locking read computes inside Cachex's single
  # Locksmith process, which every other locking read on the node (the API's
  # authentication among them) would queue behind for the whole compute.
  defp settled(project, sha, opts) do
    case Commits.summary(project.id, sha) do
      %{version: version} ->
        excluded = Keyword.get_lazy(opts, :excluded, fn -> ExcludedPaths.pattern_for_project(project) end)
        settings = :erlang.phash2({excluded, GitHistory.settings(project).tracked_file_globs})
        key = [:coverage_reported, project.id, sha, version, settings]

        KeyValueStore.get_or_update(key, [ttl: @cache_ttl, locking: false], fn ->
          compute(project, sha, Keyword.put(opts, :excluded, excluded))
        end)

      nil ->
        compute(project, sha, opts)
    end
  end

  @doc """
  The commit's files with their reported line totals, by path, as
  `Tuist.Tests.Coverage.Commits.merged_files/3` lists the measured ones: what
  the comparison reads when the commit's reported coverage is exact, so its
  targets and files compare as a full run's would. `measured` are the
  commit's measured files; a file only an ancestor compiled takes its targets
  from there.
  """
  def merged_files(%Project{} = project, sha, measured, opts \\ []) do
    case settled(project, sha, opts) do
      %{kind: "reported", files: files} ->
        by_path = Map.new(measured, &{&1.path, &1})

        files
        |> Enum.map(fn {path, file} ->
          by_path
          |> Map.get(path, %{path: path, targets: Map.get(file, :targets, [])})
          |> Map.merge(Map.take(file, [:git_blob_id, :covered_lines, :executable_lines]))
        end)
        |> Enum.sort_by(& &1.path)

      _ ->
        measured
    end
  end

  @doc """
  One file of a commit whose skipped tests were all carried forward: the
  lines carried into it (those no run at the commit covered itself), and,
  for a file no run at the commit compiled, the runs its executable lines are
  read from. Nil when the commit's reported coverage is not exact or the file
  is not part of it.
  """
  def file(%Project{} = project, sha, path, opts \\ []) do
    case settled(project, sha, opts) do
      %{kind: "reported", files: %{^path => file}} = reported ->
        %{
          carried_lines: reported.carried_lines |> Map.get(path, MapSet.new()) |> Enum.sort(),
          source_run_ids: Map.get(file, :source_run_ids, [])
        }

      _ ->
        nil
    end
  end

  defp result(files, kind, skipped, carried_tests, gap_files, shas) do
    %{
      files: files,
      carried_lines: %{},
      kind: kind,
      covered_lines: files |> Map.values() |> Enum.map(& &1.covered_lines) |> Enum.sum(),
      executable_lines: files |> Map.values() |> Enum.map(& &1.executable_lines) |> Enum.sum(),
      skipped_tests_count: length(skipped),
      carried_tests_count: length(carried_tests),
      gap_files_count: gap_files,
      carried_from: shas
    }
  end

  # The files the commit's runs measured, by path, as the commit's own totals
  # count them.
  defp observed_files(project_id, run_ids, excluded) do
    from(f in subquery(Coverage.merged_files_query_for_runs(project_id, run_ids, excluded)),
      select:
        {f.path, %{git_blob_id: f.git_blob_id, covered_lines: f.covered_lines, executable_lines: f.executable_lines}}
    )
    |> ClickHouseRepo.all(settings: [select_sequential_consistency: 1])
    |> Map.new()
  end

  # The blob of every file the commit's runs reported, test code included.
  defp run_blobs(project_id, run_ids) do
    from(f in Coverage.report_files_for_runs(project_id, run_ids),
      where: f.git_blob_id != "",
      group_by: f.path,
      select: {f.path, fragment("any(?)", f.git_blob_id)}
    )
    |> ClickHouseRepo.all(settings: [select_sequential_consistency: 1])
    |> Map.new()
  end

  # The enabled candidates of the commit's runs that none of them executed,
  # with the ancestors' runs when inheriting candidates read them (nil
  # otherwise), so carrying them does not read them again.
  defp skipped_tests(project, repository_id, sha, {run_ids, hits}, schemes) do
    {inherited, ancestry} = inherited_candidates(project, repository_id, sha, {run_ids, hits}, schemes)
    candidates = Enum.uniq_by(enumerated(project.id, run_ids) ++ inherited, & &1.test_case_id)

    if candidates == [] do
      {:not_enumerated, ancestry}
    else
      ran =
        from(r in TestCaseRun,
          where: r.project_id == ^project.id and r.test_run_id in ^run_ids and not is_nil(r.test_case_id),
          distinct: true,
          select: r.test_case_id
        )
        |> ClickHouseRepo.all(settings: [select_sequential_consistency: 1])
        |> MapSet.new()

      {Enum.reject(candidates, &MapSet.member?(ran, &1.test_case_id)), ancestry}
    end
  end

  defp enumerated(_project_id, []), do: []

  defp enumerated(project_id, run_ids) do
    ClickHouseRepo.all(
      from(e in EnumeratedTest,
        where: e.project_id == ^project_id and e.test_run_id in ^run_ids,
        group_by: e.test_case_id,
        having: fragment("argMax(?, ?)", e.enabled, e.inserted_at),
        select: %{
          test_case_id: e.test_case_id,
          module_name: fragment("argMax(?, ?)", e.module_name, e.inserted_at),
          suite_name: fragment("argMax(?, ?)", e.suite_name, e.inserted_at),
          name: fragment("argMax(?, ?)", e.name, e.inserted_at)
        }
      ),
      settings: [select_sequential_consistency: 1]
    )
  end

  # A scheme selective testing skipped entirely never builds, so its run
  # carries no coverage and its client lists no candidates: nothing at the
  # commit says those tests exist, let alone that they were skipped. Their
  # candidates come from the nearest ancestor run of the same scheme, which
  # is where their evidence comes from anyway. Every other guard still
  # applies to each of them, so a test that must not be carried is still a
  # gap rather than a silent omission.
  defp silent_schemes(project_id, sha, run_ids, schemes) do
    measured = MapSet.new(schemes)

    from(t in Test,
      where: t.project_id == ^project_id and t.git_commit_sha == ^sha and t.git_dirty == false,
      distinct: true,
      select: %{id: t.id, scheme: t.scheme}
    )
    |> ClickHouseRepo.all(settings: [select_sequential_consistency: 1])
    |> Enum.reject(&(&1.scheme in [nil, ""] or MapSet.member?(measured, &1.scheme) or &1.id in run_ids))
    |> Enum.map(& &1.scheme)
    |> Enum.uniq()
  end

  defp inherited_candidates(_project, repository_id, _sha, _runs, _schemes) when repository_id in [nil, 0], do: {[], nil}

  defp inherited_candidates(project, repository_id, sha, {run_ids, hits}, schemes) do
    silent = silent_schemes(project.id, sha, run_ids, schemes)
    skipped_modules = hits |> Enum.map(& &1.name) |> Enum.uniq()

    if silent == [] and skipped_modules == [] do
      {[], nil}
    else
      ancestry = ancestor_runs(project.id, repository_id, sha)

      ranked =
        ancestry
        |> Enum.group_by(& &1.scheme)
        |> Map.new(fn {scheme, runs} -> {scheme, Enum.sort_by(runs, &source_rank/1)} end)

      {inherit_schemes(project.id, ranked, silent) ++ inherit_modules(project.id, ranked, schemes, skipped_modules),
       ancestry}
    end
  end

  # The runs of the commit's ancestors within the window, each with its
  # commit's depth. A skipped test's evidence is in the last run that
  # executed it, however far back, so the walk cannot stop at the nearest
  # measured ancestor; it is read once per compute instead.
  defp ancestor_runs(project_id, repository_id, sha) do
    depths =
      repository_id
      |> GitHistory.ancestors(sha)
      |> Enum.reject(fn {_sha, depth} -> depth == 0 end)
      |> Map.new()

    project_id
    |> Commits.runs(Map.keys(depths))
    |> Enum.map(&Map.put(&1, :depth, depths[&1.git_commit_sha]))
  end

  defp inherit_schemes(_project_id, _ranked, []), do: []

  defp inherit_schemes(project_id, ranked, silent) do
    Enum.flat_map(silent, fn scheme ->
      ranked
      |> Map.get(scheme, [])
      |> Enum.find_value([], fn run ->
        case enumerated(project_id, [run.test_run_id]) do
          [] -> nil
          candidates -> candidates
        end
      end)
    end)
  end

  # The targets selective testing skipped in the commit's runs, with the
  # hash that matched, read once for both uses: a generated project prunes
  # them from the workspace, so the run that skipped them never lists their
  # tests, and a test that is not a candidate cannot be carried; their
  # candidates come from the nearest ancestor run of the same scheme that
  # listed them. A target that is merely absent (taken out of the scheme, or
  # deleted) is not a hit, so nothing is inherited for it. Both uses need
  # the repository, so without one nothing is read.
  defp selective_testing_hits(_project_id, repository_id, _run_ids) when repository_id in [nil, 0], do: []

  defp selective_testing_hits(project_id, _repository_id, run_ids) do
    project_id
    |> target_hashes(run_ids)
    |> Enum.filter(&(&1.hit in ["local", "remote"]))
  end

  defp inherit_modules(_project_id, _ranked, _schemes, []), do: []

  defp inherit_modules(project_id, ranked, schemes, modules) do
    Enum.flat_map(schemes, fn scheme ->
      runs = ranked |> Map.get(scheme, []) |> Enum.take(@module_source_runs)
      rank = runs |> Enum.with_index() |> Map.new(fn {run, index} -> {run.test_run_id, index} end)

      project_id
      |> enumerated_by_run(Enum.map(runs, & &1.test_run_id), modules)
      |> Enum.group_by(& &1.module_name)
      |> Enum.flat_map(fn {_module, rows} ->
        nearest = rows |> Enum.map(& &1.test_run_id) |> Enum.min_by(&rank[&1])
        rows |> Enum.filter(&(&1.test_run_id == nearest)) |> Enum.map(&Map.delete(&1, :test_run_id))
      end)
    end)
  end

  defp enumerated_by_run(_project_id, [], _modules), do: []

  defp enumerated_by_run(project_id, run_ids, modules) do
    ClickHouseRepo.all(
      from(e in EnumeratedTest,
        where: e.project_id == ^project_id and e.test_run_id in ^run_ids and e.module_name in ^modules,
        group_by: [e.test_run_id, e.test_case_id],
        having: fragment("argMax(?, ?)", e.enabled, e.inserted_at),
        select: %{
          test_run_id: e.test_run_id,
          test_case_id: e.test_case_id,
          module_name: fragment("argMax(?, ?)", e.module_name, e.inserted_at),
          suite_name: fragment("argMax(?, ?)", e.suite_name, e.inserted_at),
          name: fragment("argMax(?, ?)", e.name, e.inserted_at)
        }
      ),
      settings: [select_sequential_consistency: 1]
    )
  end

  # The skipped tests whose coverage still applies, the lines they carry per
  # path, and per path the run the lines came from.
  defp carried(%{repository_id: repository_id}, _skipped) when repository_id in [nil, 0], do: {[], %{}, %{}}

  defp carried(context, skipped) do
    source_runs =
      Map.new(
        context.ancestry || ancestor_runs(context.project.id, context.repository_id, context.sha),
        &{&1.test_run_id, %{sha: &1.git_commit_sha, depth: &1.depth, ran_at: &1.ran_at}}
      )

    tests = Map.new(skipped, &{Evidence.test_scope_id(&1.module_name, &1.suite_name, &1.name), &1})
    rows = evidence_rows(context.project.id, Map.keys(tests), Map.keys(source_runs), "test")

    chosen =
      rows
      |> Enum.group_by(& &1.scope_id)
      |> Map.new(fn {scope_id, scope_rows} ->
        run_id = scope_rows |> Enum.map(& &1.test_run_id) |> Enum.uniq() |> Enum.min_by(&source_rank(source_runs[&1]))
        {scope_id, %{run_id: run_id, rows: Enum.filter(scope_rows, &(&1.test_run_id == run_id))}}
      end)

    passed = passed(context.project.id, tests, chosen)
    suites = suite_rows(context.project.id, tests, chosen)
    files = source_files(context.project.id, chosen |> Map.values() |> Enum.map(& &1.run_id) |> Enum.uniq())
    tracked_now = tracked(context, context.sha)
    validity = validity_cache(context, tracked_now, source_runs, chosen)

    candidates =
      Enum.map(chosen, fn {scope_id, %{run_id: run_id, rows: test_rows}} ->
        test = tests[scope_id]
        all_rows = test_rows ++ Map.get(suites, {run_id, Evidence.suite_scope_id(test.module_name, test.suite_name)}, [])
        {test, Map.put(source_runs[run_id], :run_id, run_id), all_rows, Map.get(files, run_id, %{})}
      end)

    context = prefetch_blobs(context, Enum.map(candidates, fn {_test, source, rows, files} -> {source, rows, files} end))

    candidates
    |> Enum.reduce({[], %{}, %{}}, fn {test, source, all_rows, source_files}, acc ->
      if MapSet.member?(passed, {test.test_case_id, source.run_id}) and
           applies?(context, validity, source, all_rows, source_files) do
        keep(acc, context, [test], all_rows, source, source_files)
      else
        acc
      end
    end)
    |> carry_targets(context, skipped, source_runs, {tracked_now, validity})
    |> then(fn {kept, lines, sources} -> {Enum.uniq_by(kept, & &1.test_case_id), lines, sources} end)
  end

  defp keep({kept, lines, sources}, context, tests, rows, source, source_files) do
    counted = Enum.filter(rows, &counted?(context, source_files, &1.path))

    {tests ++ kept,
     Enum.reduce(counted, lines, fn row, lines ->
       Map.update(lines, row.path, MapSet.new(row.line_numbers), &MapSet.union(&1, MapSet.new(row.line_numbers)))
     end), Enum.reduce(counted, sources, fn row, sources -> Map.put_new(sources, row.path, source) end)}
  end

  # A target selective testing skipped carries whole. Its evidence is
  # everything its test process executed, so carrying it is exact only when
  # none of its tests ran at the commit and they are the tests that ran then:
  # the hit says the first, and a source run that hashed the target the same
  # says the second, since the hash covers the target's sources, its tests
  # and everything they depend on. Every other guard is the per-test one: the
  # target passed there, what it executed is unchanged, so are the tracked
  # files, and the evidence holds lines. It needs no observer in the test
  # process and no serial execution, so it covers what per-test evidence
  # cannot: Swift Testing without the attribution trait, and tests that ran in
  # parallel.
  defp carry_targets(acc, context, skipped, source_runs, tracked) do
    hits = Map.new(context.hits, &{&1.name, &1.hash})

    by_module = skipped |> Enum.filter(&Map.has_key?(hits, &1.module_name)) |> Enum.group_by(& &1.module_name)

    if by_module == %{} do
      acc
    else
      carry_targets(acc, context, {by_module, hits}, source_runs, tracked, Map.keys(by_module))
    end
  end

  defp carry_targets(acc, context, {by_module, hits}, source_runs, {tracked_now, validity}, modules) do
    project_id = context.project.id
    rows = evidence_rows(project_id, modules, Map.keys(source_runs), "target")

    same_hash =
      project_id
      |> target_hashes(rows |> Enum.map(& &1.test_run_id) |> Enum.uniq())
      |> Enum.filter(&(&1.hash == hits[&1.name]))
      |> MapSet.new(&{&1.test_run_id, &1.name})

    chosen =
      rows
      |> Enum.filter(&MapSet.member?(same_hash, {&1.test_run_id, &1.scope_id}))
      |> Enum.group_by(& &1.scope_id)
      |> Map.new(fn {module, module_rows} ->
        run_id = module_rows |> Enum.map(& &1.test_run_id) |> Enum.uniq() |> Enum.min_by(&source_rank(source_runs[&1]))
        {module, %{run_id: run_id, rows: Enum.filter(module_rows, &(&1.test_run_id == run_id))}}
      end)

    failed = failed_targets(project_id, chosen)
    files = source_files(project_id, chosen |> Map.values() |> Enum.map(& &1.run_id) |> Enum.uniq())
    validity = Map.merge(validity_cache(context, tracked_now, source_runs, chosen), validity)

    context =
      prefetch_blobs(
        context,
        Enum.map(chosen, fn {_module, %{run_id: run_id, rows: rows}} ->
          {Map.put(source_runs[run_id], :run_id, run_id), rows, Map.get(files, run_id, %{})}
        end)
      )

    Enum.reduce(chosen, acc, fn {module, %{run_id: run_id, rows: target_rows}}, acc ->
      source = Map.put(source_runs[run_id], :run_id, run_id)

      if not MapSet.member?(failed, {run_id, module}) and
           applies?(context, validity, source, target_rows, Map.get(files, run_id, %{})) do
        keep(acc, context, by_module[module], target_rows, source, Map.get(files, run_id, %{}))
      else
        acc
      end
    end)
  end

  # The selective-testing hash and hit each run's command event reported per
  # target. A run that ignored selective testing still hashes its targets,
  # and reports them as misses. The targets are read by command event, which
  # their table's `proj_by_command_event` projection is ordered by: joined
  # to the events, nothing bounded the read of a table ordered by time.
  defp target_hashes(_project_id, []), do: []

  defp target_hashes(project_id, run_ids) do
    events = command_events(project_id, run_ids)

    events
    |> Map.keys()
    |> Coverage.id_chunks()
    |> Enum.flat_map(fn ids ->
      ClickHouseRepo.all(
        from(t in XcodeTarget,
          where: t.command_event_id in ^ids and not is_nil(t.selective_testing_hash),
          distinct: true,
          select: %{
            command_event_id: t.command_event_id,
            name: t.name,
            hash: t.selective_testing_hash,
            hit: t.selective_testing_hit
          }
        )
      )
    end)
    |> Enum.map(fn target ->
      target |> Map.delete(:command_event_id) |> Map.put(:test_run_id, events[target.command_event_id])
    end)
    |> Enum.uniq()
  end

  defp command_events(project_id, run_ids) do
    run_ids
    |> Coverage.id_chunks()
    |> Enum.flat_map(fn runs ->
      ClickHouseRepo.all(
        from(e in Event, where: e.project_id == ^project_id and e.test_run_id in ^runs, select: {e.id, e.test_run_id})
      )
    end)
    |> Map.new()
  end

  # The targets that had a failing test in the run their evidence comes from.
  defp failed_targets(_project_id, chosen) when chosen == %{}, do: MapSet.new()

  defp failed_targets(project_id, chosen) do
    run_ids = chosen |> Map.values() |> Enum.map(& &1.run_id) |> Enum.uniq()
    modules = Map.keys(chosen)

    from(r in TestCaseRun,
      where:
        r.project_id == ^project_id and r.test_run_id in ^run_ids and r.module_name in ^modules and
          r.status == "failure",
      distinct: true,
      select: {r.test_run_id, r.module_name}
    )
    |> ClickHouseRepo.all()
    |> MapSet.new()
  end

  defp source_rank(%{depth: depth, ran_at: ran_at}), do: {depth, -DateTime.to_unix(to_datetime(ran_at), :microsecond)}

  defp to_datetime(%DateTime{} = datetime), do: datetime
  defp to_datetime(%NaiveDateTime{} = datetime), do: DateTime.from_naive!(datetime, "Etc/UTC")

  # Evidence rows of the given scopes in the given runs, each shard's latest
  # report only.
  defp evidence_rows(_project_id, [], _run_ids, _kind), do: []
  defp evidence_rows(_project_id, _scope_ids, [], _kind), do: []

  defp evidence_rows(project_id, scope_ids, run_ids, kind) do
    run_ids
    |> Enum.chunk_every(@run_id_chunk)
    |> Enum.flat_map(fn runs ->
      scope_ids
      |> Coverage.id_chunks(length(runs))
      |> Enum.flat_map(fn chunk ->
        ClickHouseRepo.all(
          from(f in CoverageFile,
            where:
              f.project_id == ^project_id and f.scope_kind == ^kind and f.scope_id in ^chunk and
                f.test_run_id in ^runs,
            select: %{
              test_run_id: f.test_run_id,
              shard_index: f.shard_index,
              scope_id: f.scope_id,
              path: f.path,
              line_numbers: f.line_numbers,
              inserted_at: f.inserted_at
            }
          )
        )
      end)
    end)
    |> Enum.group_by(&{&1.test_run_id, &1.shard_index, &1.scope_id})
    |> Enum.flat_map(fn {_key, shard_rows} ->
      latest = shard_rows |> Enum.map(& &1.inserted_at) |> Enum.max(NaiveDateTime)
      Enum.filter(shard_rows, &(NaiveDateTime.compare(&1.inserted_at, latest) == :eq))
    end)
  end

  defp suite_rows(project_id, tests, chosen) do
    suite_ids =
      tests
      |> Map.values()
      |> Enum.reject(&(&1.suite_name == ""))
      |> Enum.map(&Evidence.suite_scope_id(&1.module_name, &1.suite_name))
      |> Enum.uniq()

    run_ids = chosen |> Map.values() |> Enum.map(& &1.run_id) |> Enum.uniq()

    project_id
    |> evidence_rows(suite_ids, run_ids, "suite")
    |> Enum.group_by(&{&1.test_run_id, &1.scope_id})
  end

  defp passed(project_id, tests, chosen) do
    pairs =
      Enum.map(chosen, fn {scope_id, %{run_id: run_id}} -> {tests[scope_id].test_case_id, run_id} end)

    run_ids = pairs |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

    case_ids = pairs |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

    run_ids
    |> Enum.chunk_every(@run_id_chunk)
    |> Enum.flat_map(fn runs ->
      case_ids
      |> Coverage.id_chunks(length(runs))
      |> Enum.flat_map(fn chunk ->
        ClickHouseRepo.all(
          from(r in TestCaseRun,
            where:
              r.project_id == ^project_id and r.test_case_id in ^chunk and r.test_run_id in ^runs and
                r.status == "success",
            select: {r.test_case_id, r.test_run_id}
          )
        )
      end)
    end)
    |> MapSet.new()
  end

  # What each source run reported per path: the blob, whether it is test
  # code, and the executable lines.
  defp source_files(_project_id, []), do: %{}

  defp source_files(project_id, run_ids) do
    run_ids
    |> Coverage.id_chunks()
    |> Enum.flat_map(fn runs ->
      ClickHouseRepo.all(
        from(f in Coverage.report_files_for_runs(project_id, runs),
          select: %{
            test_run_id: f.test_run_id,
            path: f.path,
            git_blob_id: f.git_blob_id,
            is_test: f.is_test,
            line_numbers: f.line_numbers
          }
        )
      )
    end)
    |> Enum.group_by(& &1.test_run_id)
    |> Map.new(fn {run_id, rows} ->
      {run_id,
       rows
       |> Enum.group_by(& &1.path)
       |> Map.new(fn {path, path_rows} ->
         {path,
          %{
            git_blob_id: path_rows |> Enum.map(& &1.git_blob_id) |> Enum.find("", &(&1 != "")),
            is_test: Enum.all?(path_rows, & &1.is_test),
            line_numbers: path_rows |> Enum.flat_map(& &1.line_numbers) |> MapSet.new()
          }}
       end)}
    end)
  end

  # Tracked files are compared once per source commit evidence was chosen
  # from, not per ancestor.
  defp validity_cache(context, now, source_runs, chosen) do
    chosen
    |> Map.values()
    |> Enum.map(&source_runs[&1.run_id].sha)
    |> Enum.uniq()
    |> Map.new(fn sha -> {sha, now != :unknown and tracked(context, sha) == now} end)
  end

  defp tracked(%{project: project, repository_id: repository_id}, sha) do
    cond do
      GitHistory.settings(project).tracked_file_globs == [] -> []
      GitHistory.listing_stored?(repository_id, sha) -> GitHistory.tracked_files(project, repository_id, sha)
      true -> :unknown
    end
  end

  defp applies?(context, validity, source, rows, source_files) do
    paths = rows |> Enum.map(& &1.path) |> Enum.uniq()

    validity[source.sha] and
      Enum.all?(rows, &(&1.line_numbers != [] or not counted?(context, source_files, &1.path))) and
      same_blobs?(context, source, paths, source_files)
  end

  defp counted?(context, source_files, path) do
    not ExcludedPaths.excluded?(context.excluded, path) and
      case Map.get(source_files, path) do
        %{is_test: is_test} -> not is_test
        nil -> false
      end
  end

  defp same_blobs?(context, %{sha: source_sha}, paths, source_files) do
    now = blobs_now(context, paths)

    then_blobs =
      case {Enum.reject(paths, &match?(%{git_blob_id: <<_, _::binary>>}, Map.get(source_files, &1))), context} do
        {[], _context} -> %{}
        {_missing, %{then_blobs: %{^source_sha => cached}}} -> cached
        {missing, _context} -> GitHistory.blobs_at(context.repository_id, source_sha, missing)
      end

    Enum.all?(paths, fn path ->
      before = source_files |> get_in([path, :git_blob_id]) |> blank_to_nil() || Map.get(then_blobs, path)
      is_binary(before) and before != "" and Map.get(now, path) == before
    end)
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  # A path's blob at the commit: what a run measured says it, and the commit's
  # listing says it for the files no run compiled.
  defp blobs_now(context, paths) do
    {known, unknown} = Enum.split_with(paths, &Map.has_key?(context.blobs, &1))

    context.blobs
    |> Map.take(known)
    |> Map.merge(GitHistory.blobs_at(context.repository_id, context.sha, unknown))
  end

  # Every blob the checks of a set of candidates will read, fetched once: at
  # the commit for every path their evidence touches (a path the listing lacks
  # is recorded as unknown, so it is not asked again), and at each source
  # commit for the paths its run reported no blob for. Asked per candidate it
  # was a round trip per skipped test, seconds on a suite of thousands.
  defp prefetch_blobs(context, entries) do
    paths = entries |> Enum.flat_map(fn {_source, rows, _files} -> Enum.map(rows, & &1.path) end) |> Enum.uniq()
    unknown = Enum.reject(paths, &Map.has_key?(context.blobs, &1))

    blobs =
      unknown
      |> Map.new(&{&1, nil})
      |> Map.merge(GitHistory.blobs_at(context.repository_id, context.sha, unknown))
      |> Map.merge(context.blobs)

    then_blobs =
      entries
      |> Enum.group_by(fn {source, _rows, _files} -> source.sha end)
      |> Map.new(fn {sha, group} ->
        missing =
          group
          |> Enum.flat_map(fn {_source, rows, files} ->
            rows |> Enum.map(& &1.path) |> Enum.reject(&match?(%{git_blob_id: <<_, _::binary>>}, Map.get(files, &1)))
          end)
          |> Enum.uniq()

        {sha, GitHistory.blobs_at(context.repository_id, sha, missing)}
      end)

    context |> Map.put(:blobs, blobs) |> Map.put(:then_blobs, Map.merge(Map.get(context, :then_blobs, %{}), then_blobs))
  end

  defp add_carried_lines(files, _context, _run_ids, carried_lines, _sources) when carried_lines == %{}, do: files

  defp add_carried_lines(files, context, _run_ids, carried_lines, sources) do
    {observed_paths, unbuilt_paths} = carried_lines |> Map.keys() |> Enum.split_with(&Map.has_key?(files, &1))
    line_counts = Commits.line_counts(context.project.id, context.sha, observed_paths, excluded: nil)

    files =
      Enum.reduce(observed_paths, files, fn path, files ->
        counts = Map.get(line_counts, path, [])
        executable = MapSet.new(counts, &elem(&1, 0))
        covered = for {line, count} <- counts, count > 0, into: MapSet.new(), do: line
        carried = MapSet.intersection(carried_lines[path], executable)

        if counts == [] do
          files
        else
          Map.update!(files, path, &%{&1 | covered_lines: MapSet.size(MapSet.union(covered, carried))})
        end
      end)

    source_files = source_files(context.project.id, unbuilt_paths |> Enum.map(&sources[&1].run_id) |> Enum.uniq())

    Enum.reduce(unbuilt_paths, files, fn path, files ->
      case get_in(source_files, [sources[path].run_id, path]) do
        %{line_numbers: executable, git_blob_id: git_blob_id} ->
          Map.put(files, path, %{
            git_blob_id: git_blob_id,
            source_run_ids: [sources[path].run_id],
            covered_lines: MapSet.size(MapSet.intersection(carried_lines[path], executable)),
            executable_lines: MapSet.size(executable)
          })

        nil ->
          files
      end
    end)
  end

  # The files the nearest ancestor that measured one of the schemes measured
  # here counted in them, that no run at the commit compiled. Unchanged, they
  # keep their executable lines; what the ancestor covered in them has to have
  # been carried in full, or the file is a gap: some of its coverage came from
  # tests the commit's runs never listed (a target pruned from the workspace)
  # or from code that ran outside any test. Changed, they are a gap; gone from
  # the listing, they are gone. With no such ancestor, what the runs did not
  # build is unknown, which is a gap too.
  defp add_unbuilt_files(files, %{repository_id: repository_id}, _schemes) when repository_id in [nil, 0], do: {files, 0}

  defp add_unbuilt_files(files, _context, []), do: {files, 0}

  defp add_unbuilt_files(files, context, schemes) do
    case basis_run_ids(context, schemes) do
      [] -> {files, 1}
      basis_run_ids -> add_unbuilt_files(files, context, context.repository_id, basis_run_ids)
    end
  end

  defp add_unbuilt_files(files, context, repository_id, basis_run_ids) do
    missing =
      from(f in subquery(Coverage.merged_files_query_for_runs(context.project.id, basis_run_ids, nil)))
      |> ClickHouseRepo.all()
      |> Enum.reject(&(Map.has_key?(context.observed, &1.path) or ExcludedPaths.excluded?(context.excluded, &1.path)))

    now = GitHistory.blobs_at(repository_id, context.sha, Enum.map(missing, & &1.path))
    listed? = GitHistory.listing_stored?(repository_id, context.sha)

    Enum.reduce(missing, {files, 0}, fn file, {files, gaps} ->
      cond do
        not listed? ->
          {files, gaps + 1}

        not Map.has_key?(now, file.path) ->
          {Map.delete(files, file.path), gaps}

        now[file.path] != file.git_blob_id or file.git_blob_id == "" ->
          {Map.delete(files, file.path), gaps + 1}

        true ->
          carried = Map.get(files, file.path, %{covered_lines: 0}).covered_lines

          {Map.put(files, file.path, %{
             git_blob_id: file.git_blob_id,
             source_run_ids: basis_run_ids,
             targets: file.targets,
             covered_lines: carried,
             executable_lines: file.executable_lines
           }), if(carried < file.covered_lines, do: gaps + 1, else: gaps)}
      end
    end)
  end

  defp basis_run_ids(context, schemes) do
    case Commits.nearest_measured_ancestor(context.project.id, context.repository_id, context.sha, schemes) do
      {basis, _distance} ->
        context.project.id
        |> Commits.runs(basis)
        |> Enum.filter(&(&1.scheme in schemes))
        |> Enum.map(& &1.test_run_id)

      nil ->
        []
    end
  end
end
