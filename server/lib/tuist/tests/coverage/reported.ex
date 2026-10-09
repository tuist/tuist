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

  @listing_read_paths 900

  # Scope ids per evidence read: each is bound twice, once to find each
  # shard's latest report and once to read it.
  @scope_chunk 800

  @doc """
  The commit's reported coverage, or nil when no run measured it.

  `kind` is `measured` when the runs listed their candidates, skipped none
  of them, and measured every
  file the nearest ancestor that measured the same schemes covered;
  `reported` when every skipped test was carried forward exactly and no file
  is left out; and `observed` otherwise, the figure being what the runs
  measured. Carrying is all or nothing: one test or file that can't be
  accounted for exactly makes the figure `observed`, with `gap_reasons`
  saying why.
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

      place = %{project: project, repository_id: repository_id, sha: sha, observed: observed, excluded: excluded}
      skipped = skipped_tests(project, repository_id, sha, {run_ids, hits, clean}, schemes)
      settle(skipped, place, runs, {run_ids, hits, covered_schemes})
    end
  end

  # The runs listed no candidates, so what they skipped can't be told.
  defp settle({:not_enumerated, _ancestry}, place, _runs, _runs_context),
    do: result(place.observed, "observed", [], [], {0, []}, [])

  # Nothing listed was skipped, but a target selective testing skipped whose
  # tests no run listed (pruned from the workspace, and no ancestor run
  # listed them) still left its coverage out.
  defp settle({[], _ancestry}, place, _runs, {run_ids, hits, schemes}) do
    if unlisted_hits?(place.project.id, run_ids, hits),
      do: result(place.observed, "observed", [], [], {0, [:no_evidence]}, []),
      else: measured(place, schemes)
  end

  defp settle({skipped, ancestry}, place, _runs, runs) do
    context = %{repository_id: place.repository_id, sha: place.sha, ancestry: ancestry}
    carry(place.project, context, runs, place.observed, skipped, place.excluded)
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
      run_ids: run_ids,
      hits: hits,
      observed: observed,
      blobs: run_blobs(project.id, run_ids),
      excluded: ExcludedPaths.compile(excluded),
      excluded_pattern: excluded
    }

    {context, {units, reasons}} =
      if changes_tracked_files?(context) do
        {Map.put(context, :ancestry, []), {[], Map.new(skipped, &{&1.test_case_id, :tracked_file_changed})}}
      else
        # Read once: carrying and explaining the gaps both walk the ancestors' runs.
        ancestry = if(repository_id in [nil, 0], do: [], else: ancestry || ancestor_runs(project.id, repository_id, sha))
        context = Map.put(context, :ancestry, ancestry)
        {context, carried(context, skipped)}
      end

    carried_tests = units |> Enum.flat_map(& &1.tests) |> Enum.uniq_by(& &1.test_case_id)
    kept = MapSet.new(carried_tests, & &1.test_case_id)

    listed = skipped |> Enum.map(& &1.module_name) |> Enum.uniq()

    case Enum.reject(skipped, &MapSet.member?(kept, &1.test_case_id)) do
      [] ->
        if unlisted_hits?(project.id, run_ids, hits, listed),
          do: result(observed, "observed", skipped, carried_tests, {0, [:no_evidence]}, []),
          else: carry_lines(context, {observed, skipped, carried_tests}, units, schemes)

      gaps ->
        result(observed, "observed", skipped, carried_tests, {0, test_gap_reasons(context, gaps, reasons)}, [])
    end
  end

  # Every skipped test carries, so the lines they ran are read and merged
  # into the commit's files, and the files no run compiled are checked: what
  # the nearest ancestor covered in one has to have been carried in full.
  # Otherwise the figure is the observed one.
  defp carry_lines(context, {observed, skipped, carried_tests}, units, schemes) do
    {carried_lines, sources} = unit_lines(context, units)

    {files, gap_files, file_reasons} =
      observed
      |> add_carried_lines(context, carried_lines, sources)
      |> add_unbuilt_files(context, schemes)

    if gap_files == 0 do
      shas = units |> Enum.map(& &1.source.sha) |> Enum.uniq() |> Enum.sort()

      files
      |> result("reported", skipped, carried_tests, {0, []}, shas)
      |> Map.put(:carried_lines, carried_lines)
    else
      result(observed, "observed", skipped, carried_tests, {gap_files, file_reasons}, [])
    end
  end

  defp unlisted_hits?(project_id, run_ids, hits, listed \\ [])
  defp unlisted_hits?(_project_id, _run_ids, [], _listed), do: false

  defp unlisted_hits?(project_id, run_ids, hits, listed) do
    case hits |> Enum.map(& &1.name) |> Enum.uniq() |> Kernel.--(listed) do
      [] -> false
      modules -> not_run?(project_id, run_ids, modules)
    end
  end

  defp not_run?(project_id, run_ids, modules) do
    ran =
      from(r in TestCaseRun,
        where: r.project_id == ^project_id and r.test_run_id in ^run_ids and r.module_name in ^modules,
        distinct: true,
        select: r.module_name
      )
      |> ClickHouseRepo.all(settings: [select_sequential_consistency: 1])
      |> MapSet.new()

    Enum.any?(modules, &(not MapSet.member?(ran, &1)))
  end

  # Nothing was skipped, so the runs measured everything, unless a file the
  # nearest ancestor that measured the same schemes covered was not compiled
  # here: a module the build took from a binary cache runs uninstrumented, so
  # what the tests executed in it is unknown, and the figure is the observed
  # one. Without that ancestor or the commit's listing, nothing says a file
  # is missing.
  defp measured(place, schemes) do
    case uninstrumented(place, schemes) do
      [] ->
        result(place.observed, "measured", [], [], {0, []}, [])

      gaps ->
        reasons = gaps |> Enum.map(fn {_file, status} -> unbuilt_reason(status) end) |> Enum.uniq()
        result(place.observed, "observed", [], [], {length(gaps), reasons}, [])
    end
  end

  defp uninstrumented(%{repository_id: repository_id}, _schemes) when repository_id in [nil, 0], do: []
  defp uninstrumented(_place, []), do: []

  defp uninstrumented(place, schemes) do
    case basis_run_ids(place, schemes) do
      [] ->
        []

      basis_run_ids ->
        excluded = ExcludedPaths.compile(place.excluded)
        skip? = &(Map.has_key?(place.observed, &1) or ExcludedPaths.excluded?(excluded, &1))

        place.project.id
        |> unbuilt_files(place.repository_id, place.sha, basis_run_ids, skip?)
        |> Enum.filter(fn {file, status} -> status in [:kept, :changed] and file.covered_lines > 0 end)
    end
  end

  defp unbuilt_reason(:kept), do: :unbuilt_file_uncarried
  defp unbuilt_reason(:changed), do: :unbuilt_file_changed

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

  # The enabled candidates of the commit's runs that none of them executed,
  # with the ancestors' runs when inheriting candidates read them (nil
  # otherwise), so carrying them does not read them again.
  defp skipped_tests(project, repository_id, sha, {run_ids, _hits, _clean} = runs, schemes) do
    {inherited, ancestry} = inherited_candidates(project, repository_id, sha, runs, schemes)
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
  defp silent_schemes(clean, run_ids, schemes) do
    measured = MapSet.new(schemes)

    clean
    |> Enum.reject(&(&1.scheme in [nil, ""] or MapSet.member?(measured, &1.scheme) or &1.test_run_id in run_ids))
    |> Enum.map(& &1.scheme)
    |> Enum.uniq()
  end

  defp inherited_candidates(_project, repository_id, _sha, _runs, _schemes) when repository_id in [nil, 0], do: {[], nil}

  defp inherited_candidates(project, repository_id, sha, {run_ids, hits, clean}, schemes) do
    silent = silent_schemes(clean, run_ids, schemes)
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

  # The skipped tests whose coverage still applies, as units carried from one
  # source run each, and why each of the others cannot be. A target selective
  # testing skipped is one unit; a test is one otherwise, or when its target
  # could not be carried whole. Deciding reads which files each unit's
  # evidence touches, never its lines.
  defp carried(%{repository_id: repository_id}, _skipped) when repository_id in [nil, 0], do: {[], %{}}

  defp carried(context, skipped) do
    source_runs =
      Map.new(context.ancestry, &{&1.test_run_id, %{sha: &1.git_commit_sha, depth: &1.depth, ran_at: &1.ran_at}})

    ranked = source_runs |> Enum.sort_by(&source_rank(elem(&1, 1))) |> Enum.map(&elem(&1, 0))

    tracked_now = tracked(context, context.sha)
    hashes = Map.new(context.hits, &{&1.name, &1.hash})
    {in_hits, others} = Enum.split_with(skipped, &Map.has_key?(hashes, &1.module_name))

    {target_units, target_reasons} =
      in_hits
      |> Enum.group_by(& &1.module_name)
      |> target_units(context.project.id, hashes, ranked, source_runs)
      |> check(context, tracked_now)

    carried_modules = MapSet.new(target_units, & &1.module)

    {test_units, test_reasons} =
      (others ++ Enum.reject(in_hits, &MapSet.member?(carried_modules, &1.module_name)))
      |> test_units(context.project.id, ranked, source_runs)
      |> check(context, tracked_now)

    {target_units ++ test_units, Map.merge(target_reasons, test_reasons)}
  end

  # A target selective testing skipped carries whole. Its evidence is
  # everything its test process executed, so carrying it is exact only when
  # none of its tests ran at the commit and they are the tests that ran then:
  # the hit says the first, and a source run that hashed the target the same
  # says the second, since the hash covers the target's sources, its tests
  # and everything they depend on. Every other guard is the per-test one. It
  # needs no observer in the test process and no serial execution, so it
  # covers what per-test evidence cannot: Swift Testing without the
  # attribution trait, and tests that ran in parallel.
  defp target_units(by_module, _project_id, _hashes, _ranked, _source_runs) when by_module == %{}, do: []

  defp target_units(by_module, project_id, hashes, ranked, source_runs) do
    held = evidence_runs(project_id, Map.keys(by_module), ranked, "target")

    same_hash =
      project_id
      |> target_hashes(held |> Enum.map(&elem(&1, 1)) |> Enum.uniq())
      |> Enum.filter(&(&1.hash == hashes[&1.name]))
      |> MapSet.new(&{&1.test_run_id, &1.name})

    held
    |> Enum.filter(fn {module, run_id} -> MapSet.member?(same_hash, {run_id, module}) end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {module, run_ids} ->
      run_id = Enum.min_by(run_ids, &source_rank(source_runs[&1]))

      %{
        kind: :target,
        key: {:module, module},
        module: module,
        tests: by_module[module],
        scopes: [{"target", module}],
        run_id: run_id,
        source: Map.put(source_runs[run_id], :run_id, run_id)
      }
    end)
  end

  defp test_units([], _project_id, _ranked, _source_runs), do: []

  defp test_units(tests, project_id, ranked, source_runs) do
    by_scope = Map.new(tests, &{Evidence.test_scope_id(&1.module_name, &1.suite_name, &1.name), &1})

    project_id
    |> nearest_runs(Map.keys(by_scope), ranked, "test")
    |> Enum.map(fn {scope_id, run_id} ->
      test = by_scope[scope_id]

      suite =
        if test.suite_name == "", do: [], else: [{"suite", Evidence.suite_scope_id(test.module_name, test.suite_name)}]

      %{
        kind: :test,
        key: test.test_case_id,
        module: test.module_name,
        tests: [test],
        scopes: [{"test", scope_id} | suite],
        run_id: run_id,
        source: Map.put(source_runs[run_id], :run_id, run_id)
      }
    end)
  end

  # Each scope's nearest run holding its evidence, picked in ClickHouse a
  # chunk of runs at a time, nearest first, so the scopes found in the
  # nearest runs are never looked for again further back.
  defp nearest_runs(_project_id, [], _ranked, _kind), do: %{}

  defp nearest_runs(project_id, scope_ids, ranked, kind) do
    ranked
    |> Enum.chunk_every(@run_id_chunk)
    |> Enum.reduce_while({scope_ids, %{}}, fn runs, {pending, found} ->
      chosen =
        for chunk <- Coverage.id_chunks(pending, 2 * length(runs)),
            {scope_id, run_id} <-
              ClickHouseRepo.all(
                from(f in CoverageFile,
                  where:
                    f.project_id == ^project_id and f.scope_kind == ^kind and f.scope_id in ^chunk and
                      f.test_run_id in ^runs,
                  group_by: f.scope_id,
                  select:
                    {f.scope_id,
                     fragment("toString(argMin(?, indexOf(?, toString(?))))", f.test_run_id, ^runs, f.test_run_id)}
                )
              ),
            into: %{},
            do: {scope_id, run_id}

      found = Map.merge(found, chosen)

      case Enum.reject(pending, &Map.has_key?(chosen, &1)) do
        [] -> {:halt, {[], found}}
        pending -> {:cont, {pending, found}}
      end
    end)
    |> elem(1)
  end

  # The units whose source still applies, and why each of the others does
  # not: the test passed there, the tracked files are the same, the evidence
  # holds lines for every file that counts, and every file it executed has
  # the same blob at the commit as at its source.
  defp check([], _context, _tracked_now), do: {[], %{}}

  defp check(units, context, tracked_now) do
    project_id = context.project.id
    validity = units |> Enum.map(& &1.source.sha) |> Enum.uniq() |> Map.new(&{&1, validity(context, tracked_now, &1)})
    failed = failed_units(project_id, units)
    {without_lines, changed} = evidence_failures(context, units)

    Enum.reduce(units, {[], %{}}, fn unit, {kept, reasons} ->
      reason =
        cond do
          MapSet.member?(failed, unit.key) -> :test_failed
          validity[unit.source.sha] != :ok -> validity[unit.source.sha]
          Enum.any?(unit.scopes, &MapSet.member?(without_lines, {unit.run_id, &1})) -> :evidence_without_lines
          Enum.any?(unit.scopes, &MapSet.member?(changed, {unit.run_id, &1})) -> :executed_file_changed
          true -> nil
        end

      if reason, do: {kept, Map.put(reasons, unit.key, reason)}, else: {[unit | kept], reasons}
    end)
  end

  # The units whose source run says they failed: a test that didn't pass
  # there, a target with any failing test there.
  defp failed_units(project_id, units) do
    {targets, tests} = Enum.split_with(units, &(&1.kind == :target))
    failed_targets = failed_targets(project_id, targets)
    passed = passed(project_id, tests)

    MapSet.new(
      Enum.filter(targets, &MapSet.member?(failed_targets, {&1.run_id, &1.module})) ++
        Enum.reject(tests, &MapSet.member?(passed, {&1.key, &1.run_id})),
      & &1.key
    )
  end

  # The scopes, by source run, whose evidence names a file that counts
  # without its lines, and those whose evidence touches a file whose blob at
  # the commit differs from the one at the source. Only which files each
  # scope touched is read, never the lines.
  defp evidence_failures(context, units) do
    units
    |> Enum.group_by(& &1.run_id)
    |> Enum.reduce({MapSet.new(), MapSet.new()}, fn {run_id, run_units}, {without_lines, changed} ->
      source = hd(run_units).source
      files = context.project.id |> source_files([run_id]) |> Map.get(run_id, %{})
      touched = run_units |> Enum.flat_map(& &1.scopes) |> Enum.uniq() |> touched_files(context.project.id, run_id)

      # A file the source run did not report is one its repository's Git
      # does not track (a submodule's): nothing holds its blob, and it never
      # counts.
      reported = Enum.filter(touched, fn {_scope, path, _lines?} -> Map.has_key?(files, path) end)

      no_lines =
        for {scope, path, false} <- reported, counted?(context, files, path), into: MapSet.new(), do: {run_id, scope}

      changed_paths = reported |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> changed_paths(context, source.sha, files)

      touched_changed =
        for {scope, path, _lines?} <- reported,
            MapSet.member?(changed_paths, path),
            into: MapSet.new(),
            do: {run_id, scope}

      {MapSet.union(without_lines, no_lines), MapSet.union(changed, touched_changed)}
    end)
  end

  # Which files each of the given scopes touched in a run, and whether it
  # recorded lines in it, each shard's latest report only.
  defp touched_files(scopes, project_id, run_id) do
    scopes
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.flat_map(fn {kind, scope_ids} ->
      for chunk <- Enum.chunk_every(scope_ids, div(@scope_chunk, 2)),
          {scope_id, path, lines?} <-
            ClickHouseRepo.all(
              from(f in latest_evidence(project_id, run_id, kind, chunk),
                group_by: [f.scope_id, f.path],
                select: {f.scope_id, f.path, fragment("min(notEmpty(?))", f.line_numbers)}
              )
            ),
          do: {{kind, scope_id}, path, lines? == 1}
    end)
  end

  # The paths whose blob at the commit differs from the one at the source
  # commit. What a run reported says a path's blob, and the commit's listing
  # says it for the files no run reported.
  defp changed_paths([], _context, _source_sha, _files), do: MapSet.new()

  defp changed_paths(paths, context, source_sha, files) do
    missing_then = Enum.reject(paths, &match?(%{git_blob_id: <<_, _::binary>>}, files[&1]))
    then_listed = GitHistory.blobs_at(context.repository_id, source_sha, missing_then)
    missing_now = Enum.reject(paths, &Map.has_key?(context.blobs, &1))
    now = Map.merge(GitHistory.blobs_at(context.repository_id, context.sha, missing_now), context.blobs)

    paths
    |> Enum.reject(fn path ->
      before = files |> get_in([path, :git_blob_id]) |> blank_to_nil() || Map.get(then_listed, path)
      is_binary(before) and before != "" and Map.get(now, path) == before
    end)
    |> MapSet.new()
  end

  # Each shard's latest report of the given scopes in a run.
  defp latest_evidence(project_id, run_id, kind, scope_ids) do
    latest =
      from(f in CoverageFile,
        where:
          f.project_id == ^project_id and f.test_run_id == ^run_id and f.scope_kind == ^kind and
            f.scope_id in ^scope_ids,
        group_by: [f.shard_index, f.scope_id],
        select: %{shard_index: f.shard_index, scope_id: f.scope_id, inserted_at: max(f.inserted_at)}
      )

    from(f in CoverageFile,
      join: l in subquery(latest),
      on: l.shard_index == f.shard_index and l.scope_id == f.scope_id and l.inserted_at == f.inserted_at,
      where:
        f.project_id == ^project_id and f.test_run_id == ^run_id and f.scope_kind == ^kind and
          f.scope_id in ^scope_ids
    )
  end

  # The lines the carried units ran in each file that counts, merged per
  # file in ClickHouse, and per file the source its lines came from (the
  # nearest when several did). What comes back is one set of lines per file,
  # however many tests and runs are carried.
  defp unit_lines(context, units) do
    project_id = context.project.id

    units
    |> Enum.group_by(& &1.run_id)
    |> Enum.sort_by(fn {_run_id, [unit | _]} -> source_rank(unit.source) end)
    |> Enum.reduce({%{}, %{}}, fn {run_id, run_units}, {lines, sources} ->
      source = hd(run_units).source

      counted =
        from(
          f in Coverage.without_excluded(Coverage.report_files_for_runs(project_id, [run_id]), context.excluded_pattern),
          where: not f.is_test,
          distinct: true,
          select: f.path
        )

      run_lines =
        run_units
        |> Enum.flat_map(& &1.scopes)
        |> Enum.uniq()
        |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
        |> Enum.flat_map(fn {kind, scope_ids} ->
          for chunk <- Enum.chunk_every(scope_ids, div(@scope_chunk, 2)),
              row <-
                ClickHouseRepo.all(
                  from(f in latest_evidence(project_id, run_id, kind, chunk),
                    where: f.path in subquery(counted),
                    group_by: f.path,
                    select: {f.path, fragment("groupUniqArrayArray(?)", f.line_numbers)}
                  )
                ),
              do: row
        end)

      Enum.reduce(run_lines, {lines, sources}, fn {path, path_lines}, {lines, sources} ->
        {Map.update(lines, path, MapSet.new(path_lines), &MapSet.union(&1, MapSet.new(path_lines))),
         Map.put_new(sources, path, source)}
      end)
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
  defp failed_targets(_project_id, []), do: MapSet.new()

  defp failed_targets(project_id, units) do
    run_ids = units |> Enum.map(& &1.run_id) |> Enum.uniq()
    modules = units |> Enum.map(& &1.module) |> Enum.uniq()

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

  # The test-run pairs, out of the carried tests and their source runs, in
  # which the test passed.
  defp passed(_project_id, []), do: MapSet.new()

  defp passed(project_id, units) do
    run_ids = units |> Enum.map(& &1.run_id) |> Enum.uniq()
    case_ids = units |> Enum.map(& &1.key) |> Enum.uniq()

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
  # code, and, when `lines:` is set, the executable lines.
  defp source_files(project_id, run_ids, opts \\ [])
  defp source_files(_project_id, [], _opts), do: %{}

  defp source_files(project_id, run_ids, opts) do
    lines? = Keyword.get(opts, :lines, false)
    paths = Keyword.get(opts, :paths)

    run_ids
    |> Coverage.id_chunks()
    |> Enum.flat_map(fn runs ->
      query = from(f in Coverage.report_files_for_runs(project_id, runs))

      queries =
        if paths,
          do: Enum.map(Coverage.id_chunks(paths, 2 * length(runs)), &where(query, [f], f.path in ^&1)),
          else: [query]

      Enum.flat_map(queries, &ClickHouseRepo.all(source_files_select(&1, lines?)))
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

  defp source_files_select(query, true),
    do:
      from(f in query,
        select: %{
          test_run_id: f.test_run_id,
          path: f.path,
          git_blob_id: f.git_blob_id,
          is_test: f.is_test,
          line_numbers: f.line_numbers
        }
      )

  defp source_files_select(query, false),
    do:
      from(f in query,
        select: %{
          test_run_id: f.test_run_id,
          path: f.path,
          git_blob_id: f.git_blob_id,
          is_test: f.is_test,
          line_numbers: fragment("CAST([] AS Array(UInt32))")
        }
      )

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

  defp counted?(context, source_files, path) do
    not ExcludedPaths.excluded?(context.excluded, path) and
      case Map.get(source_files, path) do
        %{is_test: is_test} -> not is_test
        nil -> false
      end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp add_carried_lines(files, _context, carried_lines, _sources) when carried_lines == %{}, do: files

  defp add_carried_lines(files, context, carried_lines, sources) do
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

    source_files =
      source_files(context.project.id, unbuilt_paths |> Enum.map(&sources[&1].run_id) |> Enum.uniq(),
        lines: true,
        paths: unbuilt_paths
      )

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
