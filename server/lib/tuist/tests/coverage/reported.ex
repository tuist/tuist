defmodule Tuist.Tests.Coverage.Reported do
  @moduledoc """
  A commit's **reported** coverage: what its runs observed plus the coverage
  carried forward for the tests they skipped.

  A selective run measures less than the commit is covered by: the tests it
  skipped would have covered lines too. The skipped tests are those Tuist
  skipped: every test of a target selective testing skipped (the command
  event names it as a hit, a scheme skipped whole included) and the tests
  the runs' skip identifiers name (`--skip-test-targets`, `-skip-testing`),
  less what another run of their scheme executed at the commit, plus the
  tests the commit's impact runs skipped, as their stored decisions say
  (`Tuist.TestImpactAnalysis.Carry.skipped_tests/2`). A test quarantine
  skipped is outside the suite: the client doesn't report it, so it is
  neither carried nor a gap. A target's tests are the ones it executed in
  the run recorded under the hash it was skipped with
  (`Tuist.Tests.Coverage.TargetSources`), or else in the commit's baseline
  (per scheme and platform, the checkpoint coverage-based test selection
  would decide from at the commit). What a caller's
  `-only-testing` left out was never Tuist's to skip: it is not carried,
  and the figure is a lower bound.

  Where each skipped test's coverage comes from, and its lines, are read
  from coverage-based test selection's test maps
  (`Tuist.TestImpactAnalysis.Carry` over
  `Tuist.TestImpactAnalysis.Snapshots`), never from the runs' per-test
  evidence rows, which expire after days. That coverage is carried forward
  only when it provably still applies:

  - a test coverage-based test selection skipped carries from the snapshot
    whose evidence decided it, which already proved the checks below but
    for lines; any other from the baseline's checkpoint, or from the
    overlay the commit's impact run decided from;
  - the test passed in that run;
  - every file the test executed there, and every file its suite's setup
    executed, has the same blob at the commit, and so does every tracked file
    of the project (a file the repository's Git does not track, such as a
    submodule's, has no blob to compare and never counts);
  - the evidence holds lines, not only files, for every file that counts.

  A test target selective testing skipped carries whole, from its
  processes' lines in the snapshot of the run that hashed the target the
  same way the commit's run did: the same inputs, so the same tests over
  the same code. The guards above apply to it as to a test, but for the
  blobs and the tracked files: the hash is trusted for every build input,
  so a commit that changes a tracked file still carries its targets skipped
  by hash, and nothing else.
  It needs no observer scope per test, so it covers Swift Testing without
  the attribution trait and tests that ran in parallel.

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
  alias Tuist.GitHistory
  alias Tuist.KeyValueStore
  alias Tuist.Projects.Project
  alias Tuist.TestImpactAnalysis.Baselines
  alias Tuist.TestImpactAnalysis.Carry
  alias Tuist.TestImpactAnalysis.Snapshots
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.Evidence
  alias Tuist.Tests.Coverage.ExcludedPaths
  alias Tuist.Tests.Coverage.GapReasons
  alias Tuist.Tests.Coverage.Instrumentation
  alias Tuist.Tests.Coverage.TargetSources
  alias Tuist.Tests.Coverage.Xcode
  alias Tuist.Tests.CoverageRun
  alias Tuist.Tests.Test
  alias Tuist.Tests.TestCase
  alias Tuist.Tests.TestCaseRun
  alias Tuist.Tests.TestModuleRun

  # A lookup scoped to runs binds every run id as a query parameter too, so the
  # run ids are chunked first and each chunk is kept small enough that the ids
  # it is crossed with still have room. See `Coverage.id_chunks/2`.
  @run_id_chunk 200

  @cache_ttl to_timeout(minute: 5)

  @listing_read_paths 900

  @carry_timeout to_timeout(minute: 2)

  @doc """
  The commit's reported coverage, or nil when no run measured it.

  `kind` is `measured` when Tuist skipped nothing, `reported` when every
  skipped test was carried and no file is left out, and `partial` when gaps
  remain, including a scheme whose runs reused code they couldn't measure
  (`Tuist.Tests.Coverage.Instrumentation`).
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
      {hits, skips} = unexecuted(project.id, runs, hits, runs ++ clean)

      context = %{project: project, repository_id: repository_id, sha: sha}
      skipping = skipping(context, {runs, hits, skips, clean})
      skipping = %{skipping | gaps: skipping.gaps ++ uninstrumented(project.id, runs)}

      # The hit targets that hold no tests, which a selective run's
      # checkpoint records as carried without copying a row
      # (`Tuist.TestImpactAnalysis.Snapshots.record/3`).
      empty = Map.get(skipping, :empty, [])

      if skipping.skipped == [] and skipping.gaps == [] do
        observed |> result("measured", [], [], {0, []}, []) |> Map.put(:empty_targets, empty)
      else
        context = Map.merge(context, skipping)
        context |> carry({run_ids, hits, covered_schemes}, observed, excluded) |> Map.put(:empty_targets, empty)
      end
    end
  end

  # Prebuilt code without coverage counters ran in a scheme no run of which
  # executed every test from sources: what its tests executed there is
  # unknown, so the figure is a lower bound.
  defp uninstrumented(project_id, runs) do
    if Instrumentation.incomplete_schemes(project_id, runs) == [], do: [], else: [:uninstrumented_code]
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
  # baseline carried into it. A run not set up to collect coverage, such as
  # another pipeline's test job on the same commit, says nothing about what
  # the coverage skipped; a run that didn't report it still counts.
  defp unmeasured_runs(project_id, sha) do
    ClickHouseRepo.all(
      from(t in Test.query(),
        where: t.project_id == ^project_id and t.git_commit_sha == ^sha and t.git_dirty == false,
        group_by: t.id,
        having:
          fragment("argMax(?, ?)", t.submission_auth, t.inserted_at) != "network_trusted" and
            fragment("ifNull(argMax(?, ?), true)", t.coverage_enabled, t.inserted_at),
        select: %{
          test_run_id: t.id,
          scheme: fragment("argMax(?, ?)", t.scheme, t.inserted_at),
          build_system: fragment("any(?)", t.build_system),
          git_repository_id: fragment("argMax(?, ?)", t.git_repository_id, t.inserted_at),
          skip_test_identifiers: fragment("argMax(?, ?)", t.skip_test_identifiers, t.inserted_at),
          test_impact_run_id: fragment("toString(argMax(?, ?))", t.test_impact_run_id, t.inserted_at)
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
      hits: hits,
      indexed: skipping.indexed,
      observed: observed,
      blobs: run_blobs(project.id, run_ids),
      excluded: ExcludedPaths.compile(excluded),
      baseline: skipping.baseline,
      schemes: schemes,
      impact_run_ids: skipping.impact_run_ids,
      only_hashed: Map.get(skipping, :only_hashed, false)
    }

    {units, reasons, plan} = carry_units(context, skipped)
    carried_tests = units |> Enum.flat_map(& &1.tests) |> Enum.uniq_by(& &1.test_case_id)
    # The targets carried by hash, which a selective run's checkpoint copies
    # (`Tuist.TestImpactAnalysis.Snapshots.record/3`).
    targets =
      for %{kind: :target} = unit <- units, do: Map.take(unit, [:module, :hash, :snapshot_id, :checkpoint_id, :source])

    carry = %{plan: plan, excluded: excluded, targets: targets}
    {observed, sources} = add_carried_lines(observed, context, run_ids, carry)

    {files, gap_files, file_reasons} = add_unbuilt_files(observed, context, schemes)

    kept = MapSet.new(carried_tests, & &1.test_case_id)
    gaps = Enum.reject(skipped, &MapSet.member?(kept, &1.test_case_id))
    test_reasons = test_gap_reasons(context, gaps, reasons)

    kind = if gaps == [] and gap_files == 0 and run_gaps == [], do: "reported", else: "partial"
    shas = sources |> Enum.map(& &1.sha) |> Enum.uniq() |> Enum.sort()

    files
    |> result(kind, skipped, carried_tests, {gap_files, test_reasons ++ file_reasons ++ run_gaps}, shas)
    |> Map.put(:carry, carry)
  end

  # The units carried, from snapshots (`Tuist.TestImpactAnalysis.Carry`), and
  # where their lines are read from (`Carry.plan/1`). The lines themselves
  # stay in ClickHouse: the fold reads only what they change in each file
  # (`add_carried_lines/4`), and a file's page reads that file's
  # (`carried_lines/3`).
  defp carry_units(context, skipped) do
    context =
      Map.merge(context, %{
        validity: &validity(context, &1),
        run_blobs: &run_blobs(context.project.id, &1),
        blobs_now: &blobs_now(context.repository_id, context.sha, &1),
        blobs_then: &blobs_now(context.repository_id, &1, &2)
      })

    {units, reasons} = Carry.units(context, skipped)
    {units, reasons, Carry.plan(units)}
  end

  # Which of the skipped tests a commit's own tracked-file change leaves
  # carriable: `:all` when its tracked files match some parent's, and
  # otherwise `:hashed` when targets were skipped by their hash, which is
  # trusted for every build input, or `:none`. Every ancestor's evidence
  # predates such a change, so it is decided before any of it is read. Only
  # an ancestor from before a change this commit undoes would still qualify,
  # which is not worth carrying for. A merge whose tracked files match one
  # parent's can still carry from that side. Without the listings, each
  # source is checked as usual.
  defp carriable(%{repository_id: repository_id}, _hits) when repository_id in [nil, 0], do: :all

  defp carriable(context, hits) do
    case GitHistory.parents(context.repository_id, context.sha) do
      [] ->
        :all

      parents ->
        cond do
          not Enum.all?(parents, &(validity(context, &1) == :tracked_file_changed)) -> :all
          hits != [] -> :hashed
          true -> :none
        end
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

  # Mix collects no per-test evidence, whatever its ancestors ran, and its
  # runs usually have no scheme to find a baseline by.
  defp missing_evidence_reasons(%{project: %{build_system: :mix}}, _tests), do: [:collection_off]

  defp missing_evidence_reasons(context, tests) do
    source_runs = context.baseline
    collected = Enum.filter(source_runs, &(&1.coverage_evidence_status == "collected"))
    live = live_runs(context.project.id, Enum.map(collected, & &1.test_run_id))

    cond do
      source_runs == [] ->
        [expired_ancestor_reason(context)]

      collected == [] ->
        [:collection_off]

      live == [] ->
        [:evidence_expired]

      true ->
        project_id = context.project.id
        linked = linked_targets(project_id, tests |> Enum.map(& &1.module_name) |> Enum.uniq(), live)
        overlapped = overlapped_tests(project_id, Enum.map(tests, & &1.test_case_id), live)

        # A target whose tests all overlapped records no test evidence either,
        # so the overlap is told first.
        tests
        |> Enum.map(fn test ->
          cond do
            MapSet.member?(overlapped, test.test_case_id) -> :overlapped
            not MapSet.member?(linked, test.module_name) -> :not_linked
            true -> :no_evidence
          end
        end)
        |> Enum.uniq()
    end
  end

  # Why a commit without a baseline checkpoint has no evidence: none of its
  # ancestors measured its schemes, or the nearest that did is past the test
  # maps' retention, collecting evidence or not.
  defp expired_ancestor_reason(context) do
    case Commits.nearest_measured_ancestor(context.project.id, context.repository_id, context.sha, context.schemes) do
      nil ->
        :no_ancestor

      {ancestor, _depth} ->
        runs = Commits.runs(context.project.id, ancestor)
        if Enum.any?(runs, &(&1.coverage_evidence_status == "collected")), do: :evidence_expired, else: :collection_off
    end
  end

  # The runs whose evidence carry can still read: those a checkpoint that
  # hasn't expired holds (`Tuist.TestImpactAnalysis.Snapshots`).
  defp live_runs(project_id, run_ids) do
    now = DateTime.utc_now()

    project_id
    |> Snapshots.for_runs(run_ids)
    |> Enum.filter(fn {_run_id, snapshot} ->
      snapshot.kind == :checkpoint and DateTime.after?(snapshot.expires_at, now)
    end)
    |> Enum.map(fn {run_id, _snapshot} -> run_id end)
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

  # The targets some of the runs recorded test-level evidence for. Only
  # TestCoverageAttribution records a test's own evidence; every target has
  # a `target` scope, which the client reads from Xcode's raw profiles. Read
  # from what the test case runs recorded at ingestion (`coverage_evidence`),
  # which outlives the evidence rows themselves.
  defp linked_targets(project_id, modules, run_ids) do
    run_ids
    |> Enum.chunk_every(@run_id_chunk)
    |> Enum.flat_map(fn runs ->
      ClickHouseRepo.all(
        from(r in TestCaseRun,
          where:
            r.project_id == ^project_id and r.test_run_id in ^runs and r.module_name in ^modules and
              r.coverage_evidence == "own",
          distinct: true,
          select: r.module_name
        )
      )
    end)
    |> MapSet.new()
  end

  # What the pages read (`files/3`, `file/4`) is the reported coverage
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
  The commit's files with their reported line totals and targets, by path, as
  `Tuist.Tests.Coverage.Commits.merged_files/3` lists the measured ones: what
  the comparison reads when the commit's reported coverage is exact, so its
  targets and files compare as a full run's would. A file only an ancestor
  compiled takes its targets from there. Nil when the commit's reported
  coverage is not exact.
  """
  def files(%Project{} = project, sha, opts \\ []) do
    case settled(project, sha, opts) do
      %{kind: "reported", files: files} ->
        files
        |> Enum.map(fn {path, file} ->
          Map.merge(
            %{path: path, targets: Map.get(file, :targets, [])},
            Map.take(file, [:git_blob_id, :covered_lines, :executable_lines])
          )
        end)
        |> Enum.sort_by(& &1.path)

      _ ->
        nil
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
        # Cached like the figure: a page reads the file more than once.
        key = [:coverage_carried_lines, project.id, sha, path, :erlang.phash2(reported.carry, 4_294_967_296)]

        ranges =
          KeyValueStore.get_or_update(key, [ttl: @cache_ttl, locking: false], fn ->
            project |> carried_lines(reported, [path]) |> Map.get(path, [])
          end)

        %{carried_lines: Evidence.range_lines(ranges), source_run_ids: Map.get(file, :source_run_ids, [])}

      _ ->
        nil
    end
  end

  defp result(files, kind, skipped, carried_tests, {gap_files, gap_reasons}, shas) do
    %{
      files: files,
      carry: nil,
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
  # count them, with their targets: the pages list them from here
  # (`files/3`) without merging the runs' rows again.
  defp observed_files(project_id, run_ids, excluded) do
    from(f in subquery(Coverage.merged_files_query_for_runs(project_id, run_ids, excluded)),
      select:
        {f.path,
         %{
           git_blob_id: f.git_blob_id,
           targets: f.targets,
           covered_lines: f.covered_lines,
           executable_lines: f.executable_lines
         }}
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
  # hit, the tests the runs' skip identifiers name, and the tests their
  # coverage-based test selection skipped. A target's tests are those of the
  # run recorded under the hash it was skipped with, or else those it ran at
  # the commit's baseline while its test files are unchanged.
  defp skipping(context, {runs, _hits, _skips, clean} = all) do
    selected = if caller_selected?(runs), do: [:caller_selected_tests], else: []
    impact_run_ids = impact_run_ids(runs ++ clean)
    impact_skipped = Enum.flat_map(impact_run_ids, &impact_skipped(context, &1))
    skipping = tuist_skipped(context, all, impact_skipped)
    Map.merge(skipping, %{gaps: skipping.gaps ++ selected, impact_run_ids: impact_run_ids})
  end

  # What the run's stored decision skipped, read from its bitmaps without
  # listing the baseline's tests. A run without a stored decision skipped
  # nothing carry can name.
  defp impact_skipped(%{project: project}, run_id), do: Carry.skipped_tests(project.id, run_id) || []

  # The runs' impact runs. The tests they skipped in the modules they decided
  # are left out by the client without naming them, so only the impact run
  # says which.
  defp impact_run_ids(runs) do
    runs |> Enum.map(&Map.get(&1, :test_impact_run_id)) |> Enum.reject(&(&1 in [nil, ""])) |> Enum.uniq()
  end

  defp tuist_skipped(_context, {_runs, [], [], _clean}, []), do: %{skipped: [], gaps: [], baseline: [], indexed: %{}}

  defp tuist_skipped(%{project: project, repository_id: repository_id, sha: sha} = context, runs, impact_skipped) do
    {_runs, hits, _skips, _clean} = runs

    # A commit that changes a tracked file carries nothing, but for the
    # targets skipped by their hash.
    case carriable(context, hits) do
      :none ->
        %{skipped: [], gaps: [:tracked_file_changed], baseline: [], indexed: %{}}

      carriable ->
        project
        |> skipped_tests(repository_id, sha, runs, impact_skipped)
        |> Map.put(:only_hashed, carriable == :hashed)
    end
  end

  defp skipped_tests(_project, repository_id, _sha, _runs, _impact_skipped) when repository_id in [nil, 0],
    do: %{skipped: [], gaps: [:no_ancestor], baseline: [], indexed: %{}}

  defp skipped_tests(project, repository_id, sha, {runs, hits, skips, clean}, impact_skipped) do
    # An identifier naming a test needs no target's tests to resolve it.
    {named, by_target} = Enum.split_with(skips, &match?([_module, _suite, _name], &1))
    modules = Enum.uniq(Enum.map(hits, & &1.name) ++ Enum.map(by_target, &hd/1))
    # A target recorded under the hash it was skipped with is the same target
    # that run executed, so its tests are the target's, whatever branch it ran.
    indexed = indexed_sources(project.id, repository_id, hits)
    baseline = baseline(project, sha, runs ++ clean)
    schemes = Map.new(runs ++ clean, &{&1.test_run_id, &1.scheme})
    skipped_in = Enum.group_by(hits, & &1.name, &schemes[&1.test_run_id])
    hashes = Map.new(hits, &{&1.name, &1.hash})

    {listed, list_gaps} =
      baseline_lists(project.id, {repository_id, sha}, baseline, {modules -- Map.keys(indexed), skipped_in, hashes})

    inventory =
      inventory(project.id, Map.merge(listed, Map.new(indexed, fn {module, source} -> {module, source.run_id} end)))

    candidates =
      Enum.flat_map(hits, &Map.get(inventory, &1.name, [])) ++
        Enum.flat_map(by_target, fn identifier ->
          inventory |> Map.get(hd(identifier), []) |> Enum.filter(&named?(&1, identifier))
        end) ++ named_tests(project.id, named) ++ impact_skipped

    ran = ran(project.id, Enum.map(runs, & &1.test_run_id))

    {empty, unlisted} =
      hits |> Enum.reject(&Map.has_key?(inventory, &1.name)) |> Enum.split_with(&empty?(&1, listed, list_gaps))

    %{
      skipped: candidates |> Enum.uniq_by(& &1.test_case_id) |> Enum.reject(&MapSet.member?(ran, &1.test_case_id)),
      gaps: unlisted |> Enum.map(&Map.get(list_gaps, &1.name, :target_without_history)) |> Enum.uniq(),
      empty: empty |> Enum.map(&%{module: &1.name, hash: &1.hash}) |> Enum.uniq(),
      baseline: baseline,
      indexed: indexed
    }
  end

  # A hit target that holds no tests: `baseline_lists/4` found it empty, or
  # the baseline's checkpoint copied it under its hash without a row, which
  # a checkpoint only does for a target a run skipped empty: a copied target
  # with tests is copied whole.
  defp empty?(hit, listed, list_gaps),
    do: match?({:ok, nil}, Map.fetch(list_gaps, hit.name)) or match?({:checkpoint, _id}, listed[hit.name])

  # The run each hit target was recorded under with the hash it was skipped
  # with (`Tuist.Tests.Coverage.TargetSources`).
  defp indexed_sources(_project_id, _repository_id, []), do: %{}

  defp indexed_sources(project_id, repository_id, hits) do
    project_id
    |> TargetSources.latest(repository_id, hits |> Map.new(&{&1.name, &1.hash}) |> Enum.to_list())
    |> Map.new(fn {{module, _hash}, source} -> {module, Map.put(source, :depth, nil)} end)
  end

  # The commit's baseline: for each scheme and platform its runs ran, the
  # checkpoint coverage-based test selection would decide from at this
  # commit (`Baselines.resolve/3`, the nearest ancestor with a live
  # checkpoint of the scope), with the runs it holds, each with its
  # `checkpoint` and `depth`. A checkpoint of the runs' platform is
  # preferred and any platform's taken otherwise: the lines a test covered
  # on another platform are only counted where the commit's runs compiled
  # them as executable. Read once per fold, it is the only history the
  # carry reads: which tests a skipped target holds when no run was
  # recorded under its hash, a source for a target it hashed the same way,
  # the checkpoint a skipped test carries from, and why a test has nothing
  # to carry.
  defp baseline(project, sha, runs) do
    platforms = platforms(project.id, Enum.map(runs, & &1.test_run_id))

    runs
    |> Enum.reject(&(&1.scheme in [nil, ""]))
    |> Enum.map(&{&1.scheme, Map.get(platforms, &1.test_run_id, "")})
    |> Enum.uniq()
    |> Enum.flat_map(fn {scheme, platform} -> baseline_runs(project, sha, scheme, platform) end)
    |> Enum.uniq_by(& &1.test_run_id)
  end

  defp baseline_runs(project, sha, scheme, platform) do
    scope = %{commit_sha: sha, scheme: scheme}

    with {:error, _reason} <- Baselines.resolve(project, Map.put(scope, :platform, platform), ancestors_only: true),
         {:error, _reason} <- Baselines.resolve(project, Map.put(scope, :platform, :any), ancestors_only: true) do
      []
    else
      {:ok, %{checkpoint: checkpoint, distance: depth}} ->
        held = MapSet.new(checkpoint.test_run_ids)

        project.id
        |> Commits.runs(checkpoint.commit_sha)
        |> Enum.filter(&MapSet.member?(held, &1.test_run_id))
        |> Enum.map(&Map.merge(&1, %{checkpoint: checkpoint, depth: depth}))
    end
  end

  # The platform each run's coverage recorded, "" for none.
  defp platforms(_project_id, []), do: %{}

  defp platforms(project_id, run_ids) do
    run_ids
    |> Enum.chunk_every(@run_id_chunk)
    |> Enum.flat_map(fn ids ->
      ClickHouseRepo.all(
        from(r in CoverageRun,
          where: r.project_id == ^project_id and r.test_run_id in ^ids,
          group_by: r.test_run_id,
          select: {fragment("toString(?)", r.test_run_id), fragment("argMax(?, ?)", r.platform, r.version)}
        )
      )
    end)
    |> Map.new()
  end

  # The baseline run each skipped target's tests are taken from, and why the
  # others have none. The tests a target held at the baseline still hold
  # unless one of its test files changed since, or a file was added beside
  # them; without both commits' listings that can't be told, and they are
  # taken as they were. A target the baseline's checkpoint copied from an
  # earlier one (`carried_targets`) under the hash the commit skipped it
  # with is listed from the checkpoint's rows (`{:checkpoint, id}`): its
  # runs never executed it, and the same hash means the same tests. A target
  # without tests (`empty_targets/5`) has none to list and no reason either
  # (`nil`).
  defp baseline_lists(_project_id, _commit, _baseline, {[], _skipped_in, _hashes}), do: {%{}, %{}}

  defp baseline_lists(_project_id, _commit, [], {modules, _skipped_in, _hashes}),
    do: {%{}, Map.new(modules, &{&1, :no_ancestor})}

  defp baseline_lists(project_id, {repository_id, sha}, baseline, {modules, skipped_in, hashes}) do
    by_id = Map.new(baseline, &{&1.test_run_id, &1})

    # A target in several schemes is taken from the scheme that skipped it.
    executed =
      by_id
      |> Map.keys()
      |> run_modules(modules)
      |> Enum.group_by(&elem(&1, 1), &elem(&1, 0))
      |> Map.new(fn {module, run_ids} ->
        {module, Enum.find(run_ids, hd(run_ids), &(by_id[&1].scheme in Map.get(skipped_in, module, [])))}
      end)

    test_files = test_files(project_id, Map.values(executed), modules)

    # Only the test files' directories are read, not the whole listings.
    changes =
      executed
      |> Enum.group_by(fn {_module, run_id} -> by_id[run_id].git_commit_sha end, fn {module, run_id} ->
        test_files |> Map.get({run_id, module}, []) |> Enum.map(&Path.dirname/1)
      end)
      |> Map.new(fn {from_sha, directories} ->
        {from_sha, changes(repository_id, from_sha, sha, directories |> Enum.concat() |> Enum.uniq())}
      end)

    copied = copied_targets(baseline)
    empty = empty_targets(project_id, by_id, Enum.reject(modules, &Map.has_key?(executed, &1)), skipped_in, hashes)

    Enum.reduce(modules, {%{}, %{}}, fn module, {listed, gaps} ->
      case executed[module] do
        nil ->
          cond do
            checkpoint_id = copied[{module, hashes[module]}] ->
              {Map.put(listed, module, {:checkpoint, checkpoint_id}), gaps}

            MapSet.member?(empty, module) ->
              {listed, Map.put(gaps, module, nil)}

            true ->
              {listed, Map.put(gaps, module, :target_without_history)}
          end

        run_id ->
          if changed_tests?(Map.get(test_files, {run_id, module}, []), changes[by_id[run_id].git_commit_sha]),
            do: {listed, Map.put(gaps, module, :test_list_changed)},
            else: {Map.put(listed, module, run_id), gaps}
      end
    end)
  end

  # The skipped targets that hold no tests: a baseline run of a scheme that
  # skipped one built it under the hash it was skipped with, recorded no
  # tests of it and passed. A run that failed may have crashed launching the
  # target's bundle before any test ran, so only a passed run tells an empty
  # target from one whose tests never reported.
  defp empty_targets(_project_id, _by_id, [], _skipped_in, _hashes), do: MapSet.new()

  defp empty_targets(project_id, by_id, modules, skipped_in, hashes) do
    modules = MapSet.new(modules)

    project_id
    |> Xcode.selective_testing_hashes(project_id |> passed_runs(Map.keys(by_id)) |> MapSet.to_list())
    |> Enum.filter(fn %{test_run_id: run_id, name: name, hash: hash, hit: hit} ->
      MapSet.member?(modules, name) and hit not in ["local", "remote"] and hash == hashes[name] and
        by_id[run_id].scheme in Map.get(skipped_in, name, [])
    end)
    |> MapSet.new(& &1.name)
  end

  defp passed_runs(project_id, run_ids) do
    for ids <- Enum.chunk_every(run_ids, @run_id_chunk),
        id <-
          ClickHouseRepo.all(
            from(t in Test.query(),
              where: t.project_id == ^project_id and t.id in ^ids,
              group_by: t.id,
              having: fragment("argMax(?, ?)", t.status, t.inserted_at) == "success",
              select: t.id
            )
          ),
        into: MapSet.new(),
        do: id
  end

  # The baseline's checkpoint that copied each target under each hash,
  # nearest first.
  defp copied_targets(baseline) do
    baseline
    |> Enum.uniq_by(& &1.checkpoint.id)
    |> Enum.sort_by(& &1.depth, :desc)
    |> Enum.flat_map(fn %{checkpoint: checkpoint} ->
      Enum.map(checkpoint.carried_targets, fn key ->
        [module, hash] = String.split(key, "\u001F", parts: 2)
        {{module, hash}, checkpoint.id}
      end)
    end)
    |> Map.new()
  end

  # The test files each of the given runs compiled into the given targets'
  # test bundles.
  defp test_files(_project_id, [], _modules), do: %{}

  defp test_files(project_id, run_ids, modules) do
    modules = MapSet.new(modules)

    from(f in Coverage.report_files_for_runs(project_id, Enum.uniq(run_ids), lines: false),
      where: f.is_test,
      distinct: true,
      select: {fragment("toString(?)", f.test_run_id), f.path, f.targets}
    )
    |> ClickHouseRepo.all()
    |> Enum.flat_map(fn {run_id, path, targets} ->
      for target <- targets, module = Path.rootname(target), MapSet.member?(modules, module), do: {{run_id, module}, path}
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  # The paths in the given directories that changed or were added between
  # two commits, or `:unknown` without both commits' complete listings.
  defp changes(_repository_id, _from_sha, _to_sha, []), do: %{changed: MapSet.new(), added: MapSet.new()}

  defp changes(repository_id, from_sha, to_sha, directories) do
    case GitHistory.changed_files(repository_id, from_sha, to_sha, directories: directories) do
      :unknown ->
        :unknown

      files ->
        {added, changed} = Enum.split_with(files, &is_nil(&1.from))
        %{changed: MapSet.new(changed, & &1.path), added: MapSet.new(added, & &1.path)}
    end
  end

  defp changed_tests?(_files, :unknown), do: false
  defp changed_tests?([], _changes), do: false

  defp changed_tests?(files, %{changed: changed, added: added}) do
    directories = MapSet.new(files, &Path.dirname/1)
    Enum.any?(files, &MapSet.member?(changed, &1)) or Enum.any?(added, &MapSet.member?(directories, Path.dirname(&1)))
  end

  # The tests identifiers name by target, suite and test, with or without the
  # parentheses of an XCTest method.
  defp named_tests(_project_id, []), do: []

  defp named_tests(project_id, identifiers) do
    names = Enum.flat_map(identifiers, fn [_module, _suite, name] -> [name, name <> "()"] end)

    from(t in TestCase,
      where:
        t.project_id == ^project_id and t.module_name in ^Enum.map(identifiers, &hd/1) and
          t.suite_name in ^Enum.map(identifiers, &Enum.at(&1, 1)) and t.name in ^names,
      distinct: true,
      select: %{
        test_case_id: fragment("toString(?)", t.id),
        module_name: t.module_name,
        suite_name: t.suite_name,
        name: t.name
      }
    )
    |> ClickHouseRepo.all()
    |> Enum.filter(fn test -> Enum.any?(identifiers, &(hd(&1) == test.module_name and named?(test, &1))) end)
  end

  # The runs' skip identifiers, split into their target, suite and test. A
  # suite or test name that holds a `/` (an ExUnit describe such as
  # `create_order/2`) arrives percent-encoded, as does a `%`.
  defp skip_identifiers(runs) do
    runs
    |> Enum.flat_map(&Map.get(&1, :skip_test_identifiers, []))
    |> Enum.uniq()
    |> Enum.map(fn identifier -> identifier |> String.split("/", parts: 3) |> Enum.map(&decode_part/1) end)
    |> Enum.reject(&(hd(&1) == ""))
  end

  defp decode_part(part) do
    if String.contains?(part, "%"), do: URI.decode(part), else: part
  rescue
    ArgumentError -> part
  end

  # What a run that measured the commit executed is in the commit's figure,
  # whichever other run skipped it, so it is neither carried nor a gap. A
  # target a run executed, and that its `-only-testing` doesn't name, ran
  # whole there, but for the tests that run's own skip identifiers name, which
  # stay skipped. For a target only a run of the same scheme counts: another
  # scheme's test plan can run other tests of the same target. A named test
  # that ran counts in any scheme, as `ran/2` does for the rest. Decided before
  # anything else, so a full run beside a selective one at the commit measures
  # what the selective one skipped whatever the commit changed.
  defp unexecuted(_project_id, [], hits, skipping), do: {hits, skip_identifiers(skipping)}

  defp unexecuted(project_id, runs, hits, skipping) do
    schemes = Map.new(runs ++ skipping, &{&1.test_run_id, &1.scheme})
    skips = skipping |> Enum.flat_map(fn run -> Enum.map(skip_identifiers([run]), &{run.scheme, &1}) end) |> Enum.uniq()
    by_id = Map.new(runs, &{&1.test_run_id, &1})
    modules = Enum.uniq(Enum.map(hits, & &1.name) ++ Enum.map(skips, fn {_scheme, [module | _]} -> module end))
    executed = run_modules(Map.keys(by_id), modules)

    whole = whole_targets(executed, by_id, [:only_test_identifiers])
    untouched = whole_targets(executed, by_id, [:only_test_identifiers, :skip_test_identifiers])

    {named, by_target} = Enum.split_with(skips, &match?({_scheme, [_module, _suite, _name]}, &1))
    by_target = Enum.reject(by_target, fn {scheme, [module | _]} -> MapSet.member?(untouched, {scheme, module}) end)

    {Enum.reject(hits, &MapSet.member?(whole, {schemes[&1.test_run_id], &1.name})),
     Enum.uniq(Enum.map(by_target, &elem(&1, 1)) ++ unexecuted_named(project_id, named, Map.keys(by_id)))}
  end

  # The targets each run executed, from its module rows: they are keyed by
  # run, so this reads the runs' own rows, not the project's test history.
  defp run_modules(run_ids, modules) do
    for runs <- Enum.chunk_every(run_ids, @run_id_chunk),
        modules <- Coverage.id_chunks(modules, length(runs)),
        pair <-
          ClickHouseRepo.all(
            from(m in TestModuleRun,
              where: m.test_run_id in ^runs and m.name in ^modules and m.test_case_count > 0,
              distinct: true,
              select: {m.test_run_id, m.name}
            ),
            settings: [select_sequential_consistency: 1]
          ),
        do: pair
  end

  # The scheme and target of each run's executed targets that none of the
  # given identifiers of that run name.
  defp whole_targets(executed, by_id, fields) do
    for {run_id, module} <- executed,
        run = by_id[run_id],
        module not in Enum.flat_map(fields, &named_targets(Map.get(run, &1, []))),
        into: MapSet.new(),
        do: {run.scheme, module}
  end

  defp named_targets(identifiers), do: Enum.map(identifiers, &(&1 |> String.split("/", parts: 2) |> hd()))

  # The identifiers naming a test none of the runs executed. One that names no
  # known test skips nothing.
  defp unexecuted_named(_project_id, [], _run_ids), do: []

  defp unexecuted_named(project_id, named, run_ids) do
    identifiers = named |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
    tests = named_tests(project_id, identifiers)
    ran = ran(project_id, run_ids, tests |> Enum.map(& &1.test_case_id) |> Enum.uniq())
    unexecuted = Enum.reject(tests, &MapSet.member?(ran, &1.test_case_id))

    Enum.filter(identifiers, fn [module | _] = identifier ->
      Enum.any?(unexecuted, &(&1.module_name == module and named?(&1, identifier)))
    end)
  end

  # `-skip-testing` names an XCTest method with or without its parentheses.
  defp named?(_test, [_module]), do: true

  defp named?(test, [_module, part]),
    do: test.suite_name == part or (test.suite_name == "" and same_name?(test.name, part))

  defp named?(test, [_module, suite, name]), do: test.suite_name == suite and same_name?(test.name, name)

  defp same_name?(name, name), do: true
  defp same_name?(name, given), do: name == given <> "()"

  defp inventory(project_id, sources) do
    sources
    |> Enum.group_by(&elem(&1, 1), &elem(&1, 0))
    |> Enum.flat_map(fn
      {{:checkpoint, checkpoint_id}, modules} -> checkpoint_tests(project_id, checkpoint_id, modules)
      {run_id, run_modules} -> run_tests(project_id, run_id, run_modules)
    end)
    |> Enum.group_by(& &1.module_name)
  end

  # A checkpoint's tests of the given targets, named from `test_cases`.
  defp checkpoint_tests(project_id, checkpoint_id, modules) do
    """
    SELECT DISTINCT toString(t.test_case_id), t.module_name, t.suite_name, c.name
    FROM test_impact_snapshot_tests AS t FINAL
    LEFT JOIN (
      SELECT DISTINCT id, name FROM test_cases
      WHERE project_id = {project_id:Int64} AND module_name IN {modules:Array(String)}
    ) AS c ON c.id = t.test_case_id
    WHERE t.project_id = {project_id:Int64} AND t.snapshot_id = {snapshot_id:UUID} AND t.module_name IN {modules:Array(String)}
    """
    |> Snapshots.query!(%{project_id: project_id, snapshot_id: checkpoint_id, modules: modules})
    |> Enum.map(fn [test_case_id, module_name, suite_name, name] ->
      %{test_case_id: test_case_id, module_name: module_name, suite_name: suite_name, name: name}
    end)
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

  # Which of the given tests the runs executed.
  defp ran(project_id, run_ids, test_case_ids) do
    for ids <- Coverage.id_chunks(test_case_ids, length(run_ids)),
        id <-
          ClickHouseRepo.all(
            from(r in TestCaseRun,
              where: r.project_id == ^project_id and r.test_run_id in ^run_ids and r.test_case_id in ^ids,
              distinct: true,
              select: r.test_case_id
            ),
            settings: [select_sequential_consistency: 1]
          ),
        into: MapSet.new(),
        do: id
  end

  # Whether every run of a scheme executed only the tests its caller selected.
  defp caller_selected?(runs) do
    runs
    |> Enum.group_by(& &1.scheme, &(Map.get(&1, :only_test_identifiers, []) != []))
    |> Enum.any?(fn {_scheme, selected} -> Enum.all?(selected) end)
  end

  # The targets selective testing skipped in the commit's runs, with the hash
  # that matched. A target that is merely absent from a run is not a hit.
  defp selective_testing_hits(_project_id, repository_id, _run_ids) when repository_id in [nil, 0], do: []

  defp selective_testing_hits(project_id, _repository_id, run_ids) do
    project_id
    |> Xcode.selective_testing_hashes(run_ids)
    |> Enum.filter(&(&1.hit in ["local", "remote"]))
  end

  # Whether evidence from `sha` holds at the commit as far as the tracked
  # files go: none of them differs between the two.
  defp validity(%{project: project, repository_id: repository_id} = context, sha) do
    case GitHistory.settings(project).tracked_file_globs do
      [] ->
        :ok

      globs ->
        case GitHistory.changed_files(repository_id, sha, context.sha, match: ExcludedPaths.pattern(globs)) do
          [] -> :ok
          :unknown -> :listing_missing
          _changed -> :tracked_file_changed
        end
    end
  end

  @doc """
  The lines carried into the given files of a commit's reported coverage
  (`compute/3`), or into all of them when `paths` is nil, as ranges
  (`Evidence.line_ranges/1`) by path: those its skipped tests covered, read
  from the snapshots its fold carried from.
  """
  def carried_lines(project, reported, paths \\ nil)

  def carried_lines(_project, %{carry: %{plan: []}}, _paths), do: %{}
  def carried_lines(_project, %{carry: nil}, _paths), do: %{}
  def carried_lines(_project, _reported, []), do: %{}

  def carried_lines(%Project{} = project, %{carry: %{plan: plan, excluded: excluded}}, paths) do
    {carried, params} = Carry.lines_sql(project.id, plan, paths: paths, excluded: excluded)

    """
    SELECT path, arraySort(arrayDistinct(groupArrayArray(lines))) FROM (#{carried}) GROUP BY path
    """
    |> ClickHouseRepo.query!(params, settings: [select_sequential_consistency: 1], timeout: @carry_timeout)
    |> Map.fetch!(:rows)
    |> Map.new(fn [path, lines] -> {path, Evidence.line_ranges(lines)} end)
  end

  # What the carried lines add to the files. One query merges each file's
  # carried lines (`Carry.lines_sql/3`) with what the commit's runs executed
  # in it, or, for a file no run at the commit compiled, with the lines its
  # source run reported, and returns counts only: no file's lines reach
  # Elixir. A file's lines come from every source that carried any, and the
  # file from the nearest of them. Returns the files and the sources that
  # were nearest for any file.
  defp add_carried_lines(files, _context, _run_ids, %{plan: []}), do: {files, []}

  defp add_carried_lines(files, context, run_ids, %{plan: plan, excluded: excluded}) do
    project_id = context.project.id
    {carried, params} = Carry.lines_sql(project_id, plan, excluded: excluded)
    source_runs = plan |> Enum.map(& &1.source.run_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    observed = Coverage.inline_sql(Coverage.report_files_for_runs(project_id, run_ids))
    sources = Coverage.inline_sql(Coverage.report_files_for_runs(project_id, source_runs))

    # The carried lines are read once, as the joins' left side: ClickHouse
    # runs a CTE again wherever it is named, and they are the costly part.
    # A source run's file only counts when no run at the commit observed it,
    # which the observed side of the same row tells: filtering the source
    # runs' rows by the observed paths read the commit's runs a second time.
    rows =
      """
      SELECT c.path, c.nearest,
        o.path != '', length(o.executable),
        length(arrayDistinct(arrayConcat(o.covered, arrayIntersect(c.carried_lines, o.executable)))),
        o.path = '' AND u.path != '', u.git_blob_id, u.targets, length(u.executable),
        length(arrayIntersect(c.carried_lines, u.executable))
      FROM (
        SELECT path, min(rank) AS nearest, argMin(source_run, rank) AS nearest_run,
          arrayDistinct(groupArrayArray(lines)) AS carried_lines
        FROM (#{carried}) GROUP BY path
      ) AS c
      LEFT JOIN (
        SELECT path, groupUniqArrayArray(line_numbers) AS executable,
          groupUniqArrayArray(arrayFilter((l, c) -> c > 0, line_numbers, execution_counts)) AS covered
        FROM (#{observed}) WHERE NOT is_test
        GROUP BY path
      ) AS o ON o.path = c.path
      LEFT JOIN (
        SELECT toString(test_run_id) AS run, path, anyIf(git_blob_id, git_blob_id != '') AS git_blob_id,
          groupUniqArrayArray(targets) AS targets, groupUniqArrayArray(line_numbers) AS executable
        FROM (#{sources})
        GROUP BY test_run_id, path
      ) AS u ON u.path = c.path AND u.run = c.nearest_run
      SETTINGS join_use_nulls = 0
      """
      |> ClickHouseRepo.query!(params, settings: [select_sequential_consistency: 1], timeout: @carry_timeout)
      |> Map.fetch!(:rows)

    files =
      Enum.reduce(rows, files, fn
        [path, rank, observed?, executable, covered, unbuilt?, git_blob_id, targets, unbuilt_executable, carried],
        files ->
          cond do
            Map.has_key?(files, path) ->
              # A file whose rows hold no lines keeps the counts its report gave it.
              if observed? in [true, 1] and executable > 0,
                do: Map.update!(files, path, &%{&1 | covered_lines: covered}),
                else: files

            unbuilt? in [true, 1] ->
              Map.put(files, path, %{
                git_blob_id: git_blob_id,
                targets: targets,
                source_run_ids: [Enum.at(plan, rank).source.run_id],
                covered_lines: carried,
                executable_lines: unbuilt_executable
              })

            true ->
              files
          end
      end)

    nearest = rows |> Enum.map(&Enum.at(&1, 1)) |> Enum.uniq() |> Enum.map(&Enum.at(plan, &1).source)
    {files, nearest}
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
