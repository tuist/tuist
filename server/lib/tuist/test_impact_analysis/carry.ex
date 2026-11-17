defmodule Tuist.TestImpactAnalysis.Carry do
  @moduledoc """
  Coverage carry from snapshots (`Tuist.TestImpactAnalysis.Snapshots`):
  where each test a commit's runs skipped carries its coverage from, and the
  lines it carries. `Tuist.Tests.Coverage.Reported` decides which tests were
  skipped and applies the result; this module is where the evidence comes
  from, and says which tests an impact run skipped (`skipped_tests/2`). Tests
  and lines come from the snapshots' tables (`test_impact_snapshot_*`,
  `test_impact_line_*`, `test_impact_run_decisions`), never from the runs'
  `test`, `suite` and `target` evidence in `coverage_files`, which expires
  long before the snapshots do; blobs come from the runs' reports (their
  `run` scope, through `context.run_blobs`).

  A test module selective testing skipped carries whole from the snapshot of
  the run recorded under the hash it was skipped with
  (`Tuist.Tests.Coverage.TargetSources`), or of a baseline run that hashed
  it the same way: the module's processes' lines there. The
  hash covers the module's sources and dependencies, so its files aren't
  compared blob by blob.

  Any other skipped test carries from the checkpoint at its scheme's
  baseline (the nearest measured ancestor `Reported` reads) when none of the
  files it or its suite's setup executed changed between that commit and
  this one: the same bitmap check selection makes (`Candidate`). Its lines
  are its own and its suite's setup's. A test the baseline can't carry
  that the commit's impact run skipped through another snapshot, the
  branch's previous run (`Tuist.TestImpactAnalysis.Decision`), carries from
  that overlay when its files are unchanged since that run.

  Both keep `Reported`'s guards: the test passed there, the tracked files
  are the same (`context.validity`), and the evidence holds lines for every
  file that counts.
  """
  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.TestImpactAnalysis.Candidate
  alias Tuist.TestImpactAnalysis.Snapshot
  alias Tuist.TestImpactAnalysis.Snapshots
  alias Tuist.Tests
  alias Tuist.Tests.Coverage.Evidence
  alias Tuist.Tests.Coverage.ExcludedPaths
  alias Tuist.Tests.Coverage.Xcode

  @doc """
  The carried units of the skipped tests, as `Reported` uses them (`kind`,
  `key`, `module`, `tests`, `run_id`, `source`), and why each of the others
  isn't carried, by test case id or `{:module, name}`. A test the snapshot
  has no evidence for gets no reason, so `Reported` explains it by what its
  ancestors collected.

  `context` holds `project`, `repository_id`, `sha`, `hits` (the modules
  skipped by hash, `%{name, hash}`), `indexed` (the run each hit module was
  recorded under with its hash, `Tuist.Tests.Coverage.TargetSources`),
  `baseline` (the baseline's runs, with
  `git_commit_sha`, `scheme` and `depth`), `impact_run_ids` (the commit's
  runs' impact runs), `excluded` (a compiled
  `Tuist.Tests.Coverage.ExcludedPaths` pattern), `blobs` (the blob of every
  file the commit's runs reported), `run_blobs` and `blobs_now`, functions
  from run ids to the blobs those runs reported and from paths to their
  blobs at the commit, and `validity`, a function from a commit to `:ok` or
  why its evidence doesn't hold here.
  """
  def units(%{repository_id: repository_id}, _skipped) when repository_id in [nil, 0], do: {[], %{}}

  def units(context, skipped) do
    hashes = Map.new(context.hits, &{&1.name, &1.hash})
    {in_hits, others} = Enum.split_with(skipped, &Map.has_key?(hashes, &1.module_name))
    {target_units, target_reasons} = in_hits |> Enum.group_by(& &1.module_name) |> target_units(context, hashes)
    carried_modules = MapSet.new(target_units, & &1.module)
    rest = others ++ Enum.reject(in_hits, &MapSet.member?(carried_modules, &1.module_name))
    {test_units, test_reasons} = test_units(rest, context)
    {target_units ++ test_units, Map.merge(target_reasons, test_reasons)}
  end

  @doc """
  The tests the impact run `run_id`'s stored decision skipped
  (`Tuist.TestImpactAnalysis.Decision`), with `test_case_id`, `module_name`
  and `suite_name`, read from its bitmaps and the snapshots that numbered
  them; nil when the run has no stored decision.
  """
  def skipped_tests(project_id, run_id) do
    params = %{project_id: project_id, run_id: run_id}

    decisions = """
    test_impact_run_decisions FINAL WHERE project_id = {project_id:Int64} AND test_impact_run_id = {run_id:UUID}
    """

    # A decision written only in part, its storing having failed midway,
    # counts as none.
    complete =
      "SELECT count() > 0 AND sum(bitmapCardinality(tests)) = any(decided) FROM #{decisions}"
      |> Snapshots.query!(params)
      |> then(fn [[complete]] -> complete in [true, 1] end)

    if complete do
      # Every number is in the numbering of the primary checkpoint
      # (`snapshot_id`), whichever snapshot's evidence decided it.
      """
      SELECT toString(test_case_id), module_name, suite_name
      FROM test_impact_snapshot_tests FINAL
      WHERE project_id = {project_id:Int64}
        AND snapshot_id IN (SELECT snapshot_id FROM #{decisions})
        AND test_idx IN (SELECT arrayJoin(bitmapToArray(tests)) FROM #{decisions} AND decision = 'skipped')
      """
      |> Snapshots.query!(params)
      |> Enum.map(fn [test_case_id, module_name, suite_name] ->
        %{test_case_id: test_case_id, module_name: module_name, suite_name: suite_name}
      end)
    end
  end

  @doc """
  The lines the units carry in each file that counts, merged per file as
  ranges (`Tuist.Tests.Coverage.Evidence.line_ranges/1`), and per file the
  source its lines came from, the nearest when several did.
  """
  def lines(context, units) do
    units
    |> Enum.group_by(& &1.snapshot_id)
    |> Enum.sort_by(fn {_snapshot_id, [unit | _]} -> source_rank(unit.source) end)
    |> Enum.reduce({%{}, %{}}, fn {snapshot_id, snapshot_units}, {lines, sources} ->
      source = hd(snapshot_units).source

      context.project.id
      |> snapshot_lines({snapshot_id, checkpoint_id(snapshot_units)}, snapshot_units)
      |> Enum.reject(fn {path, _lines} -> ExcludedPaths.excluded?(context.excluded, path) end)
      |> Enum.reduce({lines, sources}, fn {path, ranges}, {lines, sources} ->
        {Map.update(lines, path, ranges, &Evidence.line_ranges(Evidence.range_lines(&1) ++ Evidence.range_lines(ranges))),
         Map.put_new(sources, path, source)}
      end)
    end)
  end

  # Modules

  defp target_units(by_module, _context, _hashes) when by_module == %{}, do: {[], %{}}

  defp target_units(by_module, context, hashes) do
    {indexed, rest} = Enum.split_with(by_module, fn {module, _tests} -> Map.has_key?(context.indexed, module) end)

    sources =
      indexed
      |> Map.new(fn {module, _tests} -> {module, context.indexed[module]} end)
      |> Map.merge(baseline_target_sources(Map.new(rest), context, hashes))

    snapshots = Snapshots.for_runs(context.project.id, sources |> Map.values() |> Enum.map(& &1.run_id) |> Enum.uniq())

    units =
      for {module, tests} <- by_module,
          source = sources[module],
          snapshot = snapshots[source.run_id],
          snapshot != nil do
        %{
          kind: :target,
          key: {:module, module},
          module: module,
          tests: tests,
          snapshot_id: snapshot.id,
          checkpoint_id: snapshot.checkpoint_id,
          lines: %{targets: [module], suites: [], idx: []},
          run_id: source.run_id,
          source: %{sha: source.sha, depth: source.depth, ran_at: source.ran_at, run_id: source.run_id}
        }
      end

    failed = failed_modules(context.project.id, units)
    {failing, units} = Enum.split_with(units, &MapSet.member?(failed, {&1.snapshot_id, &1.module}))
    {kept, reasons} = guard(units, context)
    {kept, Map.merge(Map.new(failing, &{&1.key, :test_failed}), reasons)}
  end

  # A module no run was recorded under with its hash (`context.indexed`)
  # carries from a baseline checkpoint that holds its processes' lines when
  # that run hashed it the same way: the run whose hashes landed after its
  # fold, in local inspect mode.
  defp baseline_target_sources(by_module, _context, _hashes) when by_module == %{}, do: %{}

  defp baseline_target_sources(by_module, context, hashes) do
    checkpoints = candidates(context)

    by_id =
      Map.new(checkpoints, fn {%{checkpoint: checkpoint}, sources} ->
        {checkpoint.id, {checkpoint, sources.checkpoint.depth}}
      end)

    held =
      if by_id == %{} do
        []
      else
        # A module's rows are numbered as its lowest test (`Snapshots.scope_keys_sql/0`).
        Snapshots.query!(
          """
          WITH module_keys AS (
            SELECT snapshot_id, module_name, min(test_idx) AS test_idx FROM test_impact_snapshot_tests
            WHERE project_id = {project_id:Int64} AND snapshot_id IN {ids:Array(UUID)}
              AND module_name IN {modules:Array(String)}
            GROUP BY snapshot_id, module_name
          )
          SELECT DISTINCT toString(k.snapshot_id), k.module_name FROM test_impact_snapshot_lines AS l
          INNER JOIN module_keys AS k ON k.snapshot_id = l.snapshot_id AND k.test_idx = l.test_idx
          WHERE l.project_id = {project_id:Int64} AND l.snapshot_id IN {ids:Array(UUID)} AND l.scope = 'target'
          """,
          %{project_id: context.project.id, ids: Map.keys(by_id), modules: Map.keys(by_module)}
        )
      end

    run_ids = held |> Enum.flat_map(fn [id, _module] -> elem(by_id[id], 0).test_run_ids end) |> Enum.uniq()

    same_hash =
      context.project.id |> Xcode.selective_testing_hashes(run_ids) |> MapSet.new(&{&1.test_run_id, &1.name, &1.hash})

    held
    |> Enum.sort_by(fn [id, _module] -> elem(by_id[id], 1) end)
    |> Enum.reduce(%{}, fn [id, module], sources ->
      {checkpoint, depth} = by_id[id]
      run_id = Enum.find(checkpoint.test_run_ids, &MapSet.member?(same_hash, {&1, module, hashes[module]}))

      if run_id,
        do:
          Map.put_new(sources, module, %{
            run_id: run_id,
            sha: checkpoint.commit_sha,
            ran_at: checkpoint.ran_at,
            depth: depth
          }),
        else: sources
    end)
  end

  # The `{snapshot_id, module}` of the units whose module had a test fail in
  # the snapshot.
  defp failed_modules(_project_id, []), do: MapSet.new()

  defp failed_modules(project_id, units) do
    """
    SELECT DISTINCT toString(snapshot_id), module_name FROM test_impact_snapshot_tests FINAL
    WHERE project_id = {project_id:Int64} AND snapshot_id IN {ids:Array(UUID)} AND module_name IN {modules:Array(String)}
      AND status = 'failed'
    """
    |> Snapshots.query!(%{
      project_id: project_id,
      ids: units |> Enum.map(& &1.snapshot_id) |> Enum.uniq(),
      modules: units |> Enum.map(& &1.module) |> Enum.uniq()
    })
    |> MapSet.new(fn [id, module] -> {id, module} end)
  end

  # Tests

  defp test_units([], _context), do: {[], %{}}

  defp test_units(tests, context) do
    baseline = baseline_results(tests, context)
    from_overlays = baseline |> Enum.reject(&match?({_test, {{:ok, _unit}, _ran_at}}, &1)) |> overlay_results(context)

    {units, reasons} =
      Enum.reduce(baseline, {[], %{}}, fn {test, found}, {units, reasons} ->
        case Map.get(from_overlays, test.test_case_id, result(found)) do
          nil -> {units, reasons}
          {:gap, reason} -> {units, Map.put(reasons, test.test_case_id, reason)}
          {:ok, unit} -> {[Map.put(unit, :tests, [test]) | units], reasons}
        end
      end)

    {kept, guard_reasons} = guard(units, context)
    {kept, Map.merge(reasons, guard_reasons)}
  end

  # Each test with what the baseline's checkpoints make of it and when that
  # evidence ran (`found_at/2`). The evaluated checkpoints are dropped on
  # return, before any overlay is evaluated.
  defp baseline_results(tests, context) do
    modules = tests |> Enum.map(& &1.module_name) |> Enum.uniq()
    evaluated = context |> candidates() |> Enum.map(&evaluate(context, &1, modules))
    Enum.map(tests, fn test -> {test, Enum.find_value(evaluated, &found_at(&1, test.test_case_id))} end)
  end

  # What the overlays carry of the tests the baseline couldn't, by test case
  # id. Overlays are read only when such tests remain, and evaluated only in
  # their modules: usually the baseline carries every skipped test.
  defp overlay_results([], _context), do: %{}

  defp overlay_results(leftover, context) do
    modules = leftover |> Enum.map(fn {test, _result} -> test.module_name end) |> Enum.uniq()

    case context |> overlay_candidates() |> Enum.map(&evaluate(context, &1, modules)) do
      [] ->
        %{}

      overlays ->
        Map.new(leftover, fn {test, found} -> {test.test_case_id, or_overlay(found, overlays, test.test_case_id)} end)
    end
  end

  # The baseline's checkpoints, nearest first: one per scheme the baseline
  # measured.
  defp candidates(context) do
    context.baseline
    |> Enum.uniq_by(&{&1.git_commit_sha, &1.scheme})
    |> Enum.sort_by(& &1.depth)
    |> Enum.flat_map(fn run ->
      case Snapshots.checkpoint(context.project.id, run.git_commit_sha, run.scheme, nil) do
        nil -> []
        checkpoint -> [{%{checkpoint: checkpoint}, %{checkpoint: checkpoint_source(checkpoint, run.depth)}}]
      end
    end)
    |> Enum.uniq_by(fn {%{checkpoint: checkpoint}, _sources} -> checkpoint.id end)
  end

  defp checkpoint_source(checkpoint, depth) do
    %{sha: checkpoint.commit_sha, depth: depth, ran_at: checkpoint.ran_at, run_id: List.first(checkpoint.test_run_ids)}
  end

  # The overlays the commit's impact runs skipped tests through, newest
  # first, over their checkpoints, with the source of each layer's lines. The
  # overlay's run is keyed by the commit it reported, which `Reported` names
  # its source by; it isn't an ancestor, so it has no depth.
  defp overlay_candidates(%{impact_run_ids: []}), do: []

  defp overlay_candidates(context) do
    ids =
      """
      SELECT DISTINCT toString(evidence_snapshot_id) FROM test_impact_run_decisions
      WHERE project_id = {project_id:Int64} AND test_impact_run_id IN {run_ids:Array(UUID)}
        AND decision = 'skipped' AND evidence_snapshot_id != snapshot_id
      """
      |> Snapshots.query!(%{project_id: context.project.id, run_ids: context.impact_run_ids})
      |> Enum.map(&hd/1)

    from(s in Snapshot, where: s.id in ^ids and s.kind == :overlay and s.expires_at > ^DateTime.utc_now())
    |> Repo.all()
    |> Enum.sort_by(& &1.ran_at, {:desc, DateTime})
    |> Enum.flat_map(fn overlay ->
      run_id = List.first(overlay.test_run_ids)

      with %Snapshot{} = checkpoint <- Repo.get(Snapshot, overlay.checkpoint_id),
           {:ok, run} <- Tests.get_test(run_id) do
        [
          {%{checkpoint: checkpoint, overlay: overlay},
           %{
             checkpoint: checkpoint_source(checkpoint, depth(context, checkpoint)),
             overlay: %{sha: run.git_commit_sha, depth: nil, ran_at: overlay.ran_at, run_id: run_id}
           }}
        ]
      else
        _ -> []
      end
    end)
  end

  defp depth(context, checkpoint) do
    Enum.find_value(context.baseline, &(&1.git_commit_sha == checkpoint.commit_sha && &1.depth))
  end

  # The snapshot's tests in the modules against the files whose blob changed
  # since its commit, by test case id.
  defp evaluate(context, {layers, sources}, modules) do
    tests =
      context.project.id
      |> Candidate.evaluate(
        layers,
        context |> changed_paths(layers) |> Enum.map(&%{path: &1, affected_modules: []}),
        modules
      )
      |> Map.new(&{&1.test_case_id, &1})

    %{layers: layers, sources: sources, tests: tests}
  end

  # The files the snapshot's runs reported whose blob differs at the commit,
  # read from what the commit's runs reported and, for the rest, its
  # listing, as `Reported` compares a version's files. Evidence only names
  # reported files, so it needs no complete listing, as
  # `GitHistory.changed_files/4` does. A file reported without a blob (a
  # submodule's) never counts. An overlay's tree is its run's: a checkpoint
  # test it doesn't replace holds there with the same blobs.
  defp changed_paths(context, layers) do
    overlay_blobs =
      case Map.get(layers, :overlay) do
        nil -> %{}
        overlay -> context.run_blobs.(overlay.test_run_ids)
      end

    then = Map.merge(context.run_blobs.(layers.checkpoint.test_run_ids), overlay_blobs)
    missing = then |> Map.keys() |> Enum.reject(&Map.has_key?(context.blobs, &1))
    now = Map.merge(context.blobs_now.(missing), context.blobs)
    for {path, blob} <- then, now[path] != blob, do: path
  end

  # What the baseline can't carry an overlay may: only a test it carries is
  # taken from it, and the baseline's reason stays otherwise. A failure at
  # the baseline stands against evidence that ran before it, such as a row
  # an overlay keeps from an older checkpoint, as `Decision` decides it.
  defp or_overlay(baseline, overlays, test_case_id) do
    {result, failed_at} = baseline || {nil, nil}

    Enum.find_value(overlays, fn overlay ->
      case found_at(overlay, test_case_id) do
        {{:ok, _unit} = carried, ran_at} -> if after_failure?(result, failed_at, ran_at), do: carried
        _ -> nil
      end
    end) || result
  end

  defp after_failure?({:gap, :test_failed}, failed_at, ran_at), do: DateTime.after?(ran_at, failed_at)
  defp after_failure?(_result, _failed_at, _ran_at), do: true

  defp result(nil), do: nil
  defp result({result, _ran_at}), do: result

  # `found/2` with when the test's evidence ran: its row's layer's run.
  defp found_at(candidate, test_case_id) do
    case found(candidate, test_case_id) do
      nil -> nil
      result -> {result, Candidate.evidence_ran_at(candidate.layers, Map.fetch!(candidate.tests, test_case_id))}
    end
  end

  # A test the snapshot has no evidence for is looked up in the next one.
  defp found(%{tests: tests} = candidate, test_case_id) do
    case Map.get(tests, test_case_id) do
      nil ->
        nil

      %{status: status} when status in ["no_evidence", "stale"] ->
        nil

      %{executed_changed: true} ->
        {:gap, :executed_file_changed}

      %{status: "failed"} ->
        {:gap, :test_failed}

      test ->
        {:ok, test_unit(candidate, test)}
    end
  end

  # A test an overlay replaces has its lines there, numbered with its
  # checkpoint's; any other test has them in the checkpoint.
  defp test_unit(%{layers: layers, sources: sources}, test) do
    {snapshot_id, checkpoint_id, source} =
      case test do
        %{layer: :overlay} -> {layers.overlay.id, layers.checkpoint.id, sources.overlay}
        _ -> {layers.checkpoint.id, nil, sources.checkpoint}
      end

    %{
      kind: :test,
      key: test.test_case_id,
      module: test.module_name,
      snapshot_id: snapshot_id,
      checkpoint_id: checkpoint_id,
      lines: %{
        targets: [],
        suites: if(test.suite_name == "", do: [], else: [{test.module_name, test.suite_name}]),
        idx: [test.idx]
      },
      run_id: source.run_id,
      source: source
    }
  end

  # The units whose source still applies: its tracked files are the same as
  # the commit's, and its evidence holds lines for every file that counts.
  defp guard([], _context), do: {[], %{}}

  defp guard(units, context) do
    validity = units |> Enum.map(& &1.source.sha) |> Enum.uniq() |> Map.new(&{&1, context.validity.(&1)})
    unlined = unlined(context, units)

    Enum.reduce(units, {[], %{}}, fn unit, {kept, reasons} ->
      reason =
        cond do
          validity[unit.source.sha] != :ok -> validity[unit.source.sha]
          MapSet.member?(unlined, unit.key) -> :evidence_without_lines
          true -> nil
        end

      if reason, do: {kept, Map.put(reasons, unit.key, reason)}, else: {[unit | kept], reasons}
    end)
  end

  # The units whose evidence names a file that counts without its lines.
  defp unlined(context, units) do
    units
    |> Enum.group_by(& &1.snapshot_id)
    |> Enum.reduce(MapSet.new(), fn {snapshot_id, snapshot_units}, unlined ->
      # A suite's and a module's rows are numbered as their lowest test, whose
      # module and suite are theirs. Only the paths of the patterns without
      # lines are read: grouping every path of the snapshot's weeks peaked at
      # 2 GiB at 200k tests while those parts were unmerged, against 130 MiB.
      rows =
        """
        WITH tests AS (
          SELECT test_idx, any(module_name) AS module_name, any(suite_name) AS suite_name
          FROM test_impact_snapshot_tests
          WHERE project_id = {project_id:Int64} AND snapshot_id IN ({snapshot_id:UUID}, {checkpoint_id:UUID})
          GROUP BY test_idx
        ),
        refs AS (
          SELECT scope, test_idx, epoch, line_set FROM test_impact_snapshot_lines
          WHERE project_id = {project_id:Int64} AND snapshot_id = {snapshot_id:UUID}
        ),
        unlined AS (
          SELECT epoch, pattern, path_id FROM test_impact_line_patterns
          WHERE project_id = {project_id:Int64} AND epoch IN (SELECT epoch FROM refs) AND empty(line_ranges)
        ),
        set_patterns AS (
          SELECT epoch, line_set, pattern FROM test_impact_line_sets
          ARRAY JOIN patterns AS pattern
          WHERE project_id = {project_id:Int64} AND (epoch, line_set) IN (SELECT epoch, line_set FROM refs)
        ),
        line_paths AS (
          SELECT epoch, path_id, any(path) AS path FROM test_impact_line_paths
          WHERE project_id = {project_id:Int64} AND (epoch, path_id) IN (SELECT epoch, path_id FROM unlined)
          GROUP BY epoch, path_id
        )
        SELECT p.path, toString(r.scope), t.module_name, t.suite_name, r.test_idx FROM set_patterns AS s
        INNER JOIN unlined AS u ON u.epoch = s.epoch AND u.pattern = s.pattern
        INNER JOIN refs AS r ON r.epoch = s.epoch AND r.line_set = s.line_set
        INNER JOIN line_paths AS p ON p.epoch = u.epoch AND p.path_id = u.path_id
        LEFT JOIN tests AS t ON t.test_idx = r.test_idx
        WHERE p.path NOT IN (
            SELECT path FROM test_impact_snapshot_files
            WHERE project_id = {project_id:Int64} AND snapshot_id = {snapshot_id:UUID} AND is_test
          )
        """
        |> Snapshots.query!(%{
          project_id: context.project.id,
          snapshot_id: snapshot_id,
          checkpoint_id: checkpoint_id(snapshot_units)
        })
        |> Enum.reject(fn [path | _] -> ExcludedPaths.excluded?(context.excluded, path) end)

      keys =
        MapSet.new(rows, fn
          [_path, "test", _module, _suite, idx] -> {:test, idx}
          [_path, "suite", module, suite, _idx] -> {:suite, module, suite}
          [_path, "target", module, _suite, _idx] -> {:target, module}
        end)

      for unit <- snapshot_units, Enum.any?(unit_keys(unit), &MapSet.member?(keys, &1)), into: unlined, do: unit.key
    end)
  end

  defp unit_keys(%{lines: lines}) do
    Enum.map(lines.idx, &{:test, &1}) ++
      Enum.map(lines.suites, fn {module, suite} -> {:suite, module, suite} end) ++
      Enum.map(lines.targets, &{:target, &1})
  end

  # Lines

  # The snapshot's lines of the units' tests, their suites' setups and the
  # modules in its files that aren't test code, merged per file in
  # ClickHouse and read as ranges. The tests go as ranges of their numbers,
  # contiguous per suite and module, and ClickHouse expands them back and
  # finds their suites' and the modules' numbers (`Snapshots.scope_keys_sql/0`).
  defp snapshot_lines(project_id, {snapshot_id, checkpoint_id}, units) do
    targets = units |> Enum.flat_map(& &1.lines.targets) |> Enum.uniq()

    units
    |> Enum.flat_map(& &1.lines.idx)
    |> Snapshots.idx_chunks()
    |> then(fn
      [] -> [[]]
      chunks -> chunks
    end)
    |> Enum.with_index()
    |> Enum.flat_map(fn {chunk, i} ->
      # Modules are read once, with the first chunk of tests.
      targets = if i == 0, do: targets, else: []

      Snapshots.query!(
        """
        WITH carried AS (#{Snapshots.idx_sql()}),
        #{Snapshots.scope_keys_sql()},
        refs AS (
          SELECT epoch, line_set FROM test_impact_snapshot_lines
          WHERE project_id = {project_id:Int64} AND snapshot_id = {snapshot_id:UUID}
            AND ((scope = 'test' AND test_idx IN carried)
            OR (scope = 'suite' AND test_idx IN (
              SELECT test_idx FROM suite_keys WHERE (module_name, suite_name) IN (
                SELECT module_name, suite_name FROM numbering WHERE test_idx IN carried
              )
            ))
            OR (scope = 'target' AND test_idx IN (
              SELECT test_idx FROM module_keys WHERE module_name IN {targets:Array(String)}
            )))
        ),
        #{Snapshots.set_patterns_sql()}
        SELECT p.path, #{Snapshots.ranges_sql("l.lines")} FROM (
          -- The sets share most patterns, so each is read once, and a file's
          -- are merged by expanding their ranges.
          SELECT epoch, path_id, arraySort(arrayDistinct(arrayFlatten(arrayMap((first, last) -> range(first, last + 1),
            arrayFilter((x, i) -> i % 2 = 1, ranges, arrayEnumerate(ranges)),
            arrayFilter((x, i) -> i % 2 = 0, ranges, arrayEnumerate(ranges)))))) AS lines
          FROM (
            SELECT epoch, path_id, groupArrayArray(line_ranges) AS ranges FROM test_impact_line_patterns
            WHERE project_id = {project_id:Int64} AND epoch IN (SELECT epoch FROM refs)
              AND (epoch, pattern) IN (SELECT epoch, pattern FROM set_patterns)
            GROUP BY epoch, path_id
          )
        ) AS l
        INNER JOIN line_paths AS p ON p.epoch = l.epoch AND p.path_id = l.path_id
        WHERE p.path NOT IN (
            SELECT path FROM test_impact_snapshot_files
            WHERE project_id = {project_id:Int64} AND snapshot_id = {snapshot_id:UUID} AND is_test
          )
        """,
        %{
          project_id: project_id,
          snapshot_id: snapshot_id,
          checkpoint_id: checkpoint_id,
          idx: chunk,
          targets: targets
        }
      )
    end)
    |> Enum.map(fn [path, ranges] -> {path, Enum.chunk_every(ranges, 2)} end)
  end

  # The checkpoint whose numbering an overlay's units share, the zero UUID
  # for a checkpoint's.
  defp checkpoint_id([%{checkpoint_id: id} | _units]) when is_binary(id), do: id
  defp checkpoint_id(_units), do: "00000000-0000-0000-0000-000000000000"

  # Nearest first; a module carried by hash has no depth and comes last, as
  # `Reported` ranks its sources.
  defp source_rank(%{depth: depth, ran_at: ran_at}), do: {depth, -DateTime.to_unix(utc(ran_at), :microsecond)}

  defp utc(%DateTime{} = at), do: at
  defp utc(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")
end
