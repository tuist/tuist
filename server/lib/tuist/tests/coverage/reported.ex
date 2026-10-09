defmodule Tuist.Tests.Coverage.Reported do
  @moduledoc """
  A commit's **reported** coverage: what its runs observed plus the coverage
  carried forward for the tests they skipped.

  A selective run measures less than the commit is covered by: the tests it
  skipped would have covered lines too. The skipped tests are those Tuist
  skipped: every test of a target selective testing skipped (the command
  event names it as a hit, a scheme skipped whole included) and the tests
  the runs' skip identifiers name (quarantine, `-skip-testing`). A target's tests are the ones it executed in the nearest
  ancestor run that ran it, and per-test evidence
  (`Tuist.Tests.Coverage.Evidence`) says which lines each of them ran the
  last time it executed. What a caller's `-only-testing` left out was never
  Tuist's to skip: it is not carried, and the figure is a lower bound. That
  coverage is carried forward only when it provably still applies:

  - the evidence comes from an ancestor of the commit, from a run on a clean
    checkout, and the nearest such ancestor wins;
  - the test passed in that run;
  - every file the test executed there, and every file its suite's setup
    executed, has the same blob at the commit, and so does every tracked file
    of the project (a file the repository's Git does not track, such as a
    submodule's, has no blob to compare and never counts);
  - the evidence holds lines, not only files, for every file that counts.

  A test target selective testing skipped carries whole, from the evidence
  of the target's own process, when the source run hashed the target the
  same way the commit's run did: the same inputs, so the same tests over the
  same code. The guards above apply to it as to a test. It needs no observer
  scope per test, so it covers Swift Testing without the attribution trait
  and tests that ran in parallel.

  A skipped test that fails any of these is a **gap**: nothing is carried for
  it and the figure is a lower bound, which `kind` says (`partial`), and
  `gap_reasons` says why (`Tuist.Tests.Coverage.GapReasons`). Files an
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
  alias Tuist.Environment
  alias Tuist.GitHistory
  alias Tuist.KeyValueStore
  alias Tuist.Projects.Project
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.Evidence
  alias Tuist.Tests.Coverage.ExcludedPaths
  alias Tuist.Tests.Coverage.GapReasons
  alias Tuist.Tests.CoverageFile
  alias Tuist.Tests.Test
  alias Tuist.Tests.TestCaseRun
  alias Tuist.Xcode.XcodeTarget

  # A lookup scoped to runs binds every run id as a query parameter too, so the
  # run ids are chunked first and each chunk is kept small enough that the ids
  # it is crossed with still have room. See `Coverage.id_chunks/2`.
  @run_id_chunk 200

  @cache_ttl to_timeout(minute: 5)

  @listing_read_paths 900

  @doc """
  The commit's reported coverage, or nil when no run measured it.

  `kind` is `measured` when Tuist skipped nothing, `reported` when every
  skipped test was carried and no file is left out, and `partial` when gaps
  remain.
  """
  def compute(%Project{} = project, sha, opts \\ []) do
    runs = Keyword.get_lazy(opts, :runs, fn -> Commits.runs(project.id, sha) end)
    clean = unmeasured_runs(project.id, sha)
    unmeasured = if runs == [], do: clean, else: []

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

      # A scheme skipped whole measured nothing, and its run's hits are all
      # that say which targets it skipped.
      hits = selective_testing_hits(project.id, repository_id, Enum.uniq(run_ids ++ Enum.map(clean, & &1.test_run_id)))

      context = %{project: project, repository_id: repository_id, sha: sha}
      skipping = skipping(context, {runs, hits, skip_identifiers(runs ++ clean), clean})

      if skipping.skipped == [] and skipping.gaps == [] do
        result(observed, "measured", [], [], {0, []}, [])
      else
        context = Map.merge(context, skipping)
        carry(context, {run_ids, hits, covered_schemes}, observed, excluded)
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
        having: fragment("argMax(?, ?)", t.submission_auth, t.inserted_at) != "network_trusted",
        select: %{
          test_run_id: t.id,
          scheme: fragment("any(?)", t.scheme),
          build_system: fragment("any(?)", t.build_system),
          git_repository_id: fragment("argMax(?, ?)", t.git_repository_id, t.inserted_at),
          skip_test_identifiers: fragment("argMax(?, ?)", t.skip_test_identifiers, t.inserted_at)
        }
      ),
      settings: [select_sequential_consistency: 1]
    )
  end

  defp carry(%{project: project, repository_id: repository_id, sha: sha} = skipping, runs, observed, excluded) do
    {run_ids, hits, schemes} = runs
    %{skipped: skipped, gaps: run_gaps} = skipping

    context = %{
      project: project,
      repository_id: repository_id,
      sha: sha,
      run_ids: run_ids,
      hits: hits,
      hashes: skipping.hashes,
      observed: observed,
      blobs: run_blobs(project.id, run_ids),
      excluded: ExcludedPaths.compile(excluded),
      # Read once: carrying and explaining the gaps both walk the ancestors' runs.
      ancestry:
        if(repository_id in [nil, 0] or skipped == [],
          do: [],
          else: skipping.ancestry || ancestor_runs(project.id, repository_id, sha)
        )
    }

    {carried_tests, carried_lines, sources, reasons} = carried(context, skipped)

    {files, gap_files, file_reasons} =
      observed
      |> add_carried_lines(context, run_ids, carried_lines, sources)
      |> add_unbuilt_files(context, schemes)

    kept = MapSet.new(carried_tests, & &1.test_case_id)
    gaps = Enum.reject(skipped, &MapSet.member?(kept, &1.test_case_id))
    test_reasons = test_gap_reasons(context, gaps, reasons)

    kind = if gaps == [] and gap_files == 0 and run_gaps == [], do: "reported", else: "partial"
    shas = sources |> Map.values() |> Enum.map(& &1.sha) |> Enum.uniq() |> Enum.sort()

    files
    |> result(kind, skipped, carried_tests, {gap_files, test_reasons ++ file_reasons ++ run_gaps}, shas)
    |> Map.put(:carried_lines, carried_lines)
  end

  # A commit whose tracked files differ from every parent's carries nothing:
  # every ancestor's evidence predates the change, so it is decided before
  # any of it is read. Only an ancestor from before a change this commit
  # undoes would still qualify, which is not worth carrying for. A merge
  # whose tracked files match one parent's can still carry from that side.
  # Without the listings, each source is checked as usual.
  defp changes_tracked_files?(%{repository_id: repository_id}) when repository_id in [nil, 0], do: false

  defp changes_tracked_files?(context) do
    with now when now != :unknown <- tracked(context, context.sha),
         [_ | _] = parents <- GitHistory.parents(context.repository_id, context.sha) do
      Enum.all?(parents, &(tracked(context, &1) not in [now, :unknown]))
    else
      _ -> false
    end
  end

  # Why each skipped test that was not carried is a gap: the check its
  # evidence failed, its target's when it was skipped whole, or, without
  # evidence to check, what the ancestor runs collected.
  defp test_gap_reasons(_context, [], _reasons), do: []

  defp test_gap_reasons(context, gaps, reasons) do
    {explained, unexplained} =
      Enum.split_with(gaps, &(Map.has_key?(reasons, &1.test_case_id) or Map.has_key?(reasons, {:module, &1.module_name})))

    Enum.map(explained, &(Map.get(reasons, &1.test_case_id) || Map.fetch!(reasons, {:module, &1.module_name}))) ++
      missing_evidence_reasons(context, unexplained)
  end

  defp missing_evidence_reasons(_context, []), do: []

  defp missing_evidence_reasons(%{repository_id: repository_id}, _tests) when repository_id in [nil, 0],
    do: [:no_ancestor]

  defp missing_evidence_reasons(context, tests) do
    source_runs = context.ancestry
    collected = Enum.filter(source_runs, &(&1.coverage_evidence_status == "collected"))
    cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -Environment.coverage_retention_days().files * 86_400, :second)
    live = collected |> Enum.filter(&(NaiveDateTime.compare(&1.ran_at, cutoff) != :lt)) |> Enum.map(& &1.test_run_id)

    cond do
      source_runs == [] ->
        [:no_ancestor]

      collected == [] ->
        [:collection_off]

      live == [] ->
        [:evidence_expired]

      true ->
        project_id = context.project.id
        observed = observed_targets(project_id, tests |> Enum.map(& &1.module_name) |> Enum.uniq(), live)
        overlapped = overlapped_tests(project_id, Enum.map(tests, & &1.test_case_id), live)

        tests
        |> Enum.map(fn test ->
          cond do
            not MapSet.member?(observed, test.module_name) -> :not_linked
            MapSet.member?(overlapped, test.test_case_id) -> :overlapped
            true -> :no_evidence
          end
        end)
        |> Enum.uniq()
    end
  end

  # The tests some of the runs recorded only as overlapping another, so nothing
  # could be attributed to them.
  defp overlapped_tests(project_id, test_case_ids, run_ids) do
    test_case_ids = test_case_ids |> Enum.reject(&is_nil/1) |> Enum.uniq()

    for runs <- Enum.chunk_every(run_ids, @run_id_chunk),
        ids <- Enum.chunk_every(test_case_ids, @run_id_chunk),
        id <-
          ClickHouseRepo.all(
            from(r in TestCaseRun,
              where:
                r.project_id == ^project_id and r.test_case_id in ^ids and r.test_run_id in ^runs and
                  r.coverage_evidence == "overlapped",
              distinct: true,
              select: r.test_case_id
            )
          ),
        into: MapSet.new(),
        do: id
  end

  # The targets some of the runs recorded evidence for: a target that links
  # TestCoverageAttribution always records its process's.
  defp observed_targets(project_id, modules, run_ids) do
    run_ids
    |> Enum.chunk_every(@run_id_chunk)
    |> Enum.flat_map(fn runs ->
      ClickHouseRepo.all(
        from(f in CoverageFile,
          where:
            f.project_id == ^project_id and f.scope_kind == "target" and f.scope_id in ^modules and
              f.test_run_id in ^runs,
          distinct: true,
          select: f.scope_id
        )
      )
    end)
    |> MapSet.new()
  end

  # What the pages read (`merged_files/4`, `file/4`) is the reported coverage
  # the commit's published version settled, cached against that version: on a
  # suite of thousands a compute costs about a second and a page reads it more
  # than once. The settings that change the answer without a new version are
  # part of the key.
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

  defp result(files, kind, skipped, carried_tests, {gap_files, gap_reasons}, shas) do
    %{
      files: files,
      carried_lines: %{},
      kind: kind,
      covered_lines: files |> Map.values() |> Enum.map(& &1.covered_lines) |> Enum.sum(),
      executable_lines: files |> Map.values() |> Enum.map(& &1.executable_lines) |> Enum.sum(),
      skipped_tests_count: length(skipped),
      carried_tests_count: length(carried_tests),
      gap_files_count: gap_files,
      gap_reasons: GapReasons.encode(gap_reasons),
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
      select: {f.path, fragment("argMax(?, ?)", f.git_blob_id, f.inserted_at)}
    )
    |> ClickHouseRepo.all(settings: [select_sequential_consistency: 1])
    |> Map.new()
  end

  # What Tuist skipped at the commit: every test of a target selective testing
  # hit, and the tests the runs' skip identifiers name. A target's tests are
  # those the ancestor run that executed it ran, preferring one the caller
  # did not narrow, then one that hashed it as the hit did, then one of the
  # scheme that skipped it.
  defp skipping(context, {runs, _hits, _skips, _clean} = all) do
    selected = if caller_selected?(runs), do: [:caller_selected_tests], else: []
    skipping = tuist_skipped(context, all)
    %{skipping | gaps: skipping.gaps ++ selected}
  end

  defp tuist_skipped(_context, {_runs, [], [], _clean}), do: %{skipped: [], gaps: [], ancestry: nil, hashes: nil}

  defp tuist_skipped(%{project: project, repository_id: repository_id, sha: sha} = context, runs) do
    # A commit that changes a tracked file carries nothing.
    if changes_tracked_files?(context),
      do: %{skipped: [], gaps: [:tracked_file_changed], ancestry: [], hashes: nil},
      else: skipped_tests(project, repository_id, sha, runs)
  end

  defp skipped_tests(_project, repository_id, _sha, _runs) when repository_id in [nil, 0],
    do: %{skipped: [], gaps: [:no_ancestor], ancestry: [], hashes: nil}

  defp skipped_tests(project, repository_id, sha, {runs, hits, skips, clean}) do
    modules = Enum.uniq(Enum.map(hits, & &1.name) ++ Enum.map(skips, &hd/1))
    ancestry = ancestor_runs(project.id, repository_id, sha)
    hashes = if hits == [], do: nil, else: target_hashes(project.id, Enum.map(ancestry, & &1.test_run_id))
    schemes = runs |> Enum.concat(clean) |> Map.new(&{&1.test_run_id, &1.scheme})
    inventory = inventory(project.id, ancestry, modules, preferences(hits, skips, schemes, hashes))

    candidates =
      Enum.flat_map(hits, &Map.get(inventory, &1.name, [])) ++
        Enum.flat_map(skips, fn identifier ->
          inventory |> Map.get(hd(identifier), []) |> Enum.filter(&named?(&1, identifier))
        end)

    ran = ran(project.id, Enum.map(runs, & &1.test_run_id))

    gaps =
      cond do
        Enum.all?(hits, &Map.has_key?(inventory, &1.name)) -> []
        ancestry == [] -> [:no_ancestor]
        true -> [:target_without_history]
      end

    %{
      skipped: candidates |> Enum.uniq_by(& &1.test_case_id) |> Enum.reject(&MapSet.member?(ran, &1.test_case_id)),
      gaps: gaps,
      ancestry: ancestry,
      hashes: hashes
    }
  end

  # The runs' skip identifiers, split into their target, suite and test.
  defp skip_identifiers(runs) do
    runs
    |> Enum.flat_map(&Map.get(&1, :skip_test_identifiers, []))
    |> Enum.uniq()
    |> Enum.map(&String.split(&1, "/", parts: 3))
    |> Enum.reject(&(hd(&1) == ""))
  end

  # `-skip-testing` names an XCTest method with or without its parentheses.
  defp named?(_test, [_module]), do: true

  defp named?(test, [_module, part]),
    do: test.suite_name == part or (test.suite_name == "" and same_name?(test.name, part))

  defp named?(test, [_module, suite, name]), do: test.suite_name == suite and same_name?(test.name, name)

  defp same_name?(name, name), do: true
  defp same_name?(name, given), do: name == given <> "()"

  defp preferences(hits, skips, schemes, ancestry_hashes) do
    hit_hashes = Enum.group_by(hits, & &1.name, & &1.hash)

    same_hash =
      (ancestry_hashes || [])
      |> Enum.filter(&(&1.hash in Map.get(hit_hashes, &1.name, [])))
      |> MapSet.new(&{&1.test_run_id, &1.name})

    skipped_by =
      hits
      |> Enum.map(&{&1.name, schemes[&1.test_run_id]})
      |> Enum.concat(Enum.map(skips, &{hd(&1), nil}))
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    %{same_hash: same_hash, schemes: skipped_by}
  end

  defp inventory(_project_id, [], _modules, _preferences), do: %{}

  defp inventory(project_id, ancestry, modules, preferences) do
    by_id = Map.new(ancestry, &{&1.test_run_id, &1})

    sources =
      project_id
      |> executed_modules(Map.keys(by_id), modules)
      |> Enum.group_by(&elem(&1, 1), &by_id[elem(&1, 0)])
      |> Map.new(fn {module, runs} ->
        {module, Enum.min_by(runs, &inventory_rank(&1, module, preferences)).test_run_id}
      end)

    sources
    |> Enum.group_by(&elem(&1, 1), &elem(&1, 0))
    |> Enum.flat_map(fn {run_id, run_modules} -> run_tests(project_id, run_id, run_modules) end)
    |> Enum.group_by(& &1.module_name)
  end

  defp inventory_rank(run, module, %{same_hash: same_hash, schemes: schemes}) do
    {Map.get(run, :only_test_identifiers, []) != [], not MapSet.member?(same_hash, {run.test_run_id, module}),
     run.scheme not in Map.get(schemes, module, []), source_rank(run)}
  end

  defp executed_modules(project_id, run_ids, modules) do
    for runs <- Enum.chunk_every(run_ids, @run_id_chunk),
        pair <-
          ClickHouseRepo.all(
            from(r in TestCaseRun,
              where: r.project_id == ^project_id and r.test_run_id in ^runs and r.module_name in ^modules,
              distinct: true,
              select: {r.test_run_id, r.module_name}
            ),
            settings: [select_sequential_consistency: 1]
          ),
        do: pair
  end

  defp run_tests(project_id, run_id, modules) do
    ClickHouseRepo.all(
      from(r in TestCaseRun,
        where:
          r.project_id == ^project_id and r.test_run_id == ^run_id and r.module_name in ^modules and
            not is_nil(r.test_case_id),
        distinct: true,
        select: %{test_case_id: r.test_case_id, module_name: r.module_name, suite_name: r.suite_name, name: r.name}
      ),
      settings: [select_sequential_consistency: 1]
    )
  end

  defp ran(_project_id, []), do: MapSet.new()

  defp ran(project_id, run_ids) do
    from(r in TestCaseRun,
      where: r.project_id == ^project_id and r.test_run_id in ^run_ids and not is_nil(r.test_case_id),
      distinct: true,
      select: r.test_case_id
    )
    |> ClickHouseRepo.all(settings: [select_sequential_consistency: 1])
    |> MapSet.new()
  end

  # Whether every run of a scheme executed only the tests its caller selected.
  defp caller_selected?(runs) do
    runs
    |> Enum.group_by(& &1.scheme, &(Map.get(&1, :only_test_identifiers, []) != []))
    |> Enum.any?(fn {_scheme, selected} -> Enum.all?(selected) end)
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

  # The targets selective testing skipped in the commit's runs, with the hash
  # that matched. A target that is merely absent from a run is not a hit.
  defp selective_testing_hits(_project_id, repository_id, _run_ids) when repository_id in [nil, 0], do: []

  defp selective_testing_hits(project_id, _repository_id, run_ids) do
    project_id
    |> target_hashes(run_ids)
    |> Enum.filter(&(&1.hit in ["local", "remote"]))
  end

  # The skipped tests whose coverage still applies, the lines they carry per
  # path, and per path the run the lines came from.
  defp carried(%{repository_id: repository_id}, _skipped) when repository_id in [nil, 0], do: {[], %{}, %{}, %{}}

  defp carried(context, skipped) do
    source_runs =
      Map.new(
        context.ancestry || ancestor_runs(context.project.id, context.repository_id, context.sha),
        &{&1.test_run_id, %{sha: &1.git_commit_sha, depth: &1.depth, ran_at: &1.ran_at}}
      )

    tests = Map.new(skipped, &{Evidence.test_scope_id(&1.module_name, &1.suite_name, &1.name), &1})

    chosen =
      nearest_evidence(
        context.project.id,
        evidence_runs(context.project.id, Map.keys(tests), Map.keys(source_runs), "test"),
        source_runs,
        "test"
      )

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
    |> Enum.reduce({[], %{}, %{}, %{}}, fn {test, source, all_rows, source_files}, acc ->
      failure =
        if MapSet.member?(passed, {test.test_case_id, source.run_id}),
          do: failure(context, validity, source, all_rows, source_files),
          else: :test_failed

      if failure,
        do: put_elem(acc, 3, Map.put(elem(acc, 3), test.test_case_id, failure)),
        else: keep(acc, context, [test], all_rows, source, source_files)
    end)
    |> carry_targets(context, skipped, source_runs, {tracked_now, validity})
    |> then(fn {kept, lines, sources, reasons} -> {Enum.uniq_by(kept, & &1.test_case_id), lines, sources, reasons} end)
  end

  defp keep({kept, lines, sources, reasons}, context, tests, rows, source, source_files) do
    counted = Enum.filter(rows, &counted?(context, source_files, &1.path))

    {tests ++ kept,
     Enum.reduce(counted, lines, fn row, lines ->
       Map.update(lines, row.path, MapSet.new(row.line_numbers), &MapSet.union(&1, MapSet.new(row.line_numbers)))
     end), Enum.reduce(counted, sources, fn row, sources -> Map.put_new(sources, row.path, source) end), reasons}
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
    held = evidence_runs(project_id, modules, Map.keys(source_runs), "target")

    held_runs = MapSet.new(held, &elem(&1, 1))

    case_result =
      case context.hashes do
        nil -> target_hashes(project_id, MapSet.to_list(held_runs))
        hashes -> Enum.filter(hashes, &MapSet.member?(held_runs, &1.test_run_id))
      end

    same_hash =
      case_result
      |> Enum.filter(&(&1.hash == hits[&1.name]))
      |> MapSet.new(&{&1.test_run_id, &1.name})

    chosen =
      nearest_evidence(
        project_id,
        Enum.filter(held, fn {module, run_id} -> MapSet.member?(same_hash, {run_id, module}) end),
        source_runs,
        "target"
      )

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

      failure =
        if MapSet.member?(failed, {run_id, module}),
          do: :test_failed,
          else: failure(context, validity, source, target_rows, Map.get(files, run_id, %{}))

      if failure,
        do: put_elem(acc, 3, Map.put(elem(acc, 3), {:module, module}, failure)),
        else: keep(acc, context, by_module[module], target_rows, source, Map.get(files, run_id, %{}))
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

  # Which of the given runs hold evidence for each of the given scopes, as
  # `{scope_id, test_run_id}`, without reading its lines.
  defp evidence_runs(_project_id, [], _run_ids, _kind), do: []
  defp evidence_runs(_project_id, _scope_ids, [], _kind), do: []

  defp evidence_runs(project_id, scope_ids, run_ids, kind) do
    for runs <- Enum.chunk_every(run_ids, @run_id_chunk),
        chunk <- Coverage.id_chunks(scope_ids, length(runs)),
        held <-
          ClickHouseRepo.all(
            from(f in CoverageFile,
              where:
                f.project_id == ^project_id and f.scope_kind == ^kind and f.scope_id in ^chunk and
                  f.test_run_id in ^runs,
              distinct: true,
              select: {f.scope_id, f.test_run_id}
            )
          ),
        do: held
  end

  # Each scope's evidence from the nearest of the runs holding it, with lines
  # read only for that run: reading every ancestor run's lines to keep one
  # run's per scope exhausted the server's memory on large suites.
  defp nearest_evidence(project_id, held, source_runs, kind) do
    nearest =
      held
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Map.new(fn {scope_id, run_ids} -> {scope_id, Enum.min_by(run_ids, &source_rank(source_runs[&1]))} end)

    rows =
      nearest
      |> Enum.group_by(&elem(&1, 1), &elem(&1, 0))
      |> Enum.flat_map(fn {run_id, scope_ids} -> evidence_rows(project_id, scope_ids, [run_id], kind) end)
      |> Enum.group_by(& &1.scope_id)

    Map.new(nearest, fn {scope_id, run_id} -> {scope_id, %{run_id: run_id, rows: Map.get(rows, scope_id, [])}} end)
  end

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
  # from, not per ancestor: `:ok`, or why carrying from it is ruled out.
  defp validity_cache(context, now, source_runs, chosen) do
    chosen
    |> Map.values()
    |> Enum.map(&source_runs[&1.run_id].sha)
    |> Enum.uniq()
    |> Map.new(fn sha -> {sha, validity(context, now, sha)} end)
  end

  defp validity(_context, :unknown, _sha), do: :listing_missing

  defp validity(context, now, sha) do
    case tracked(context, sha) do
      ^now -> :ok
      :unknown -> :listing_missing
      _changed -> :tracked_file_changed
    end
  end

  defp tracked(%{project: project, repository_id: repository_id}, sha) do
    cond do
      GitHistory.settings(project).tracked_file_globs == [] -> []
      GitHistory.listing_complete?(repository_id, sha) -> GitHistory.tracked_files(project, repository_id, sha)
      true -> :unknown
    end
  end

  # Why the evidence cannot be carried from its source, or nil when it can.
  defp failure(context, validity, source, rows, source_files) do
    # A file the source run did not report is one its repository's Git does
    # not track (a submodule's): nothing holds its blob, and it never counts.
    paths = rows |> Enum.map(& &1.path) |> Enum.uniq() |> Enum.filter(&Map.has_key?(source_files, &1))

    cond do
      validity[source.sha] != :ok ->
        validity[source.sha]

      not Enum.all?(rows, &(&1.line_numbers != [] or not counted?(context, source_files, &1.path))) ->
        :evidence_without_lines

      not same_blobs?(context, source, paths, source_files) ->
        :executed_file_changed

      true ->
        nil
    end
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
  defp add_unbuilt_files(files, %{repository_id: repository_id}, _schemes) when repository_id in [nil, 0],
    do: {files, 0, []}

  defp add_unbuilt_files(files, _context, []), do: {files, 0, []}

  defp add_unbuilt_files(files, context, schemes) do
    case basis_run_ids(context, schemes) do
      [] -> {files, 1, [:unbuilt_file_unknown]}
      basis_run_ids -> add_unbuilt_files(files, context, context.repository_id, basis_run_ids)
    end
  end

  defp add_unbuilt_files(files, context, repository_id, basis_run_ids) do
    skip? = &(Map.has_key?(context.observed, &1) or ExcludedPaths.excluded?(context.excluded, &1))

    context.project.id
    |> unbuilt_files(repository_id, context.sha, basis_run_ids, skip?)
    |> Enum.reduce({files, 0, []}, fn
      {_file, :unknown}, {files, gaps, reasons} ->
        {files, gaps + 1, [:unbuilt_file_unknown | reasons]}

      {file, :gone}, {files, gaps, reasons} ->
        {Map.delete(files, file.path), gaps, reasons}

      {file, :changed}, {files, gaps, reasons} ->
        {Map.delete(files, file.path), gaps + 1, [:unbuilt_file_changed | reasons]}

      {file, :kept}, {files, gaps, reasons} ->
        carried = Map.get(files, file.path, %{covered_lines: 0}).covered_lines

        files =
          Map.put(files, file.path, %{
            git_blob_id: file.git_blob_id,
            source_run_ids: basis_run_ids,
            targets: file.targets,
            covered_lines: carried,
            executable_lines: file.executable_lines
          })

        if carried < file.covered_lines,
          do: {files, gaps + 1, [:unbuilt_file_uncarried | reasons]},
          else: {files, gaps, reasons}
    end)
    |> then(fn {files, gaps, reasons} -> {files, gaps, Enum.uniq(reasons)} end)
  end

  # The files the basis runs counted that `skip?` does not rule out, each with
  # what became of it at the commit: `:kept` with the same blob, `:changed`,
  # `:gone` from the listing, or `:unknown` when the commit has no listing.
  defp unbuilt_files(project_id, repository_id, sha, basis_run_ids, skip?) do
    missing =
      from(f in subquery(Coverage.merged_files_query_for_runs(project_id, basis_run_ids, nil)))
      |> ClickHouseRepo.all()
      |> Enum.reject(&skip?.(&1.path))

    if GitHistory.listing_complete?(repository_id, sha) do
      now = blobs_now(repository_id, sha, Enum.map(missing, & &1.path))

      Enum.map(missing, fn file ->
        cond do
          not Map.has_key?(now, file.path) -> {file, :gone}
          now[file.path] != file.git_blob_id or file.git_blob_id == "" -> {file, :changed}
          true -> {file, :kept}
        end
      end)
    else
      Enum.map(missing, &{&1, :unknown})
    end
  end

  # Past one chunk of `GitHistory.blobs_at/3`'s bound paths, reading the whole
  # listing once is cheaper than a lookup per chunk, and the unbuilt files are
  # usually most of the project.
  defp blobs_now(repository_id, sha, paths) when length(paths) > @listing_read_paths do
    repository_id |> GitHistory.commit_files(sha) |> Map.new(&{&1.path, &1.git_blob_id})
  end

  defp blobs_now(repository_id, sha, paths), do: GitHistory.blobs_at(repository_id, sha, paths)

  @doc """
  The files a published commit's reported coverage keeps from an ancestor
  although no run at the commit compiled them: those unchanged since the
  nearest ancestor that measured the commit's schemes. Only a commit whose
  runs skipped tests (`reported_kind` `reported` or `partial`) keeps any.
  `measured` are the paths the commit's runs reported. What
  `unmeasured_files_count` leaves out, so a file the figure counts is not
  also counted as having no coverage data.
  """
  def unbuilt_paths(%Project{} = project, %{reported_kind: kind} = commit, measured, excluded)
      when kind in ["reported", "partial"] and commit.git_repository_id not in [nil, 0] do
    context = %{project: project, repository_id: commit.git_repository_id, sha: commit.git_commit_sha}
    excluded = ExcludedPaths.compile(excluded)
    skip? = &(MapSet.member?(measured, &1) or ExcludedPaths.excluded?(excluded, &1))

    case basis_run_ids(context, covered_schemes(project.id, commit)) do
      [] ->
        []

      basis_run_ids ->
        for {file, :kept} <- unbuilt_files(project.id, context.repository_id, context.sha, basis_run_ids, skip?),
            do: file.path
    end
  end

  def unbuilt_paths(_project, _commit, _measured, _excluded), do: []

  # The schemes `compute/3` reads unbuilt files over: the measured ones, or,
  # for a commit every scheme was skipped whole on, those of its runs.
  defp covered_schemes(project_id, %{schemes: [], git_commit_sha: sha}) do
    project_id |> unmeasured_runs(sha) |> Enum.map(& &1.scheme) |> Enum.reject(&(&1 in [nil, ""])) |> Enum.uniq()
  end

  defp covered_schemes(_project_id, %{schemes: schemes}), do: schemes

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
