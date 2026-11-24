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
  it the same way: the module's processes' lines there. Once that snapshot
  has expired, a checkpoint that copied the module under the same hash
  stands in for it. The hash covers the module's sources and dependencies,
  so its files aren't compared blob by blob.

  A test coverage-based test selection skipped carries from the snapshot
  whose evidence decided it (`Tuist.TestImpactAnalysis.Decision`): the
  checkpoint, or the branch's previous overlay. The decision already proved
  that it passed there and that none of its files, nor a tracked file,
  changed between that snapshot and the checkout the run measured, so
  that's not evaluated again. Once that snapshot has expired, the test is
  evaluated as any other.

  Any other skipped test carries from the checkpoint at its scheme's
  baseline (the checkpoint selection would decide from at the commit, which
  `Reported` resolves) when none of the files it or its suite's setup
  executed changed between that commit and this one: the same bitmap check
  selection makes (`Candidate`). Its lines are its own and its suite's
  setup's. A test the baseline can't carry that the commit's impact run
  skipped through another snapshot carries from that overlay when its files
  are unchanged since that run.

  All keep `Reported`'s guards: the evidence holds lines for every file that
  counts, and, but for a decided test or a module carried by hash, the test
  passed there and the tracked files are the same (`context.validity`).
  """
  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.TestImpactAnalysis.Candidate
  alias Tuist.TestImpactAnalysis.Snapshot
  alias Tuist.TestImpactAnalysis.Snapshots
  alias Tuist.Tests
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
  `git_commit_sha`, `scheme`, `depth` and their `checkpoint`), `impact_run_ids` (the commit's
  runs' impact runs), `excluded` (a compiled
  `Tuist.Tests.Coverage.ExcludedPaths` pattern), `blobs` (the blob of every
  file the commit's runs reported), `run_blobs` and `blobs_now`, functions
  from run ids to the blobs those runs reported and from paths to their
  blobs at the commit, `blobs_then`, from a commit and paths to their blobs
  at that commit, `validity`, a function from a commit to `:ok` or
  why its evidence doesn't hold here, and `only_hashed`, true when the commit's own tracked-file change leaves only
  modules carried by their hash to carry.
  """
  def units(%{repository_id: repository_id}, _skipped) when repository_id in [nil, 0], do: {[], %{}}

  def units(context, skipped) do
    hashes = Map.new(context.hits, &{&1.name, &1.hash})
    {in_hits, others} = Enum.split_with(skipped, &Map.has_key?(hashes, &1.module_name))
    {target_units, target_reasons} = in_hits |> Enum.group_by(& &1.module_name) |> target_units(context, hashes)
    carried_modules = MapSet.new(target_units, & &1.module)
    rest = others ++ Enum.reject(in_hits, &MapSet.member?(carried_modules, &1.module_name))
    {test_units, test_reasons} = test_units(rest, context, target_reasons)
    {target_units ++ test_units, Map.merge(target_reasons, test_reasons)}
  end

  @doc """
  The tests the impact run `run_id`'s stored decision skipped
  (`Tuist.TestImpactAnalysis.Decision`), with `test_case_id`, `module_name`
  and `suite_name`, read from its bitmaps and the snapshots that numbered
  them; nil when the run has no stored decision. Each also has the
  `decision` that skipped it, `{snapshot_id, evidence_snapshot_id, idx}`:
  the primary checkpoint, the snapshot whose evidence decided it, and its
  number in the primary's numbering, which `units/2` carries it by.
  """
  def skipped_tests(project_id, run_id) do
    params = %{project_id: project_id, run_id: run_id}
    decisions = decisions_sql()

    # A decision written only in part, its storing having failed midway,
    # counts as none.
    complete =
      "SELECT count() > 0 AND sum(bitmapCardinality(tests)) = any(decided) FROM #{decisions}"
      |> Snapshots.query!(params)
      |> then(fn [[complete]] -> complete in [true, 1] end)

    if complete do
      # Every number is in the numbering of the primary checkpoint
      # (`snapshot_id`), whichever snapshot's evidence decided it.
      rows =
        Snapshots.query!(
          """
          SELECT toString(t.test_case_id), t.module_name, t.suite_name, t.test_idx, toString(d.snapshot_id),
            toString(d.evidence_snapshot_id)
          FROM test_impact_snapshot_tests AS t FINAL
          INNER JOIN (
            SELECT snapshot_id, evidence_snapshot_id, arrayJoin(bitmapToArray(tests)) AS test_idx
            FROM #{decisions} AND decision = 'skipped'
          ) AS d ON d.snapshot_id = t.snapshot_id AND d.test_idx = t.test_idx
          WHERE t.project_id = {project_id:Int64} AND t.snapshot_id IN (SELECT snapshot_id FROM #{decisions})
          """,
          params
        )

      # A decision names a few snapshots: each id is kept once, not per test.
      ids =
        rows
        |> Enum.flat_map(fn [_id, _module, _suite, _idx, snapshot, evidence] -> [snapshot, evidence] end)
        |> Map.new(&{&1, &1})

      Enum.map(rows, fn [test_case_id, module_name, suite_name, idx, snapshot, evidence] ->
        %{
          test_case_id: test_case_id,
          module_name: module_name,
          suite_name: suite_name,
          decision: {ids[snapshot], ids[evidence], idx}
        }
      end)
    end
  end

  @doc """
  Whether the impact run `run_id`'s whole stored decision skipped any test,
  without listing them (`skipped_tests/2`).
  """
  def skipped_any?(project_id, run_id) do
    """
    SELECT count() > 0 AND sum(bitmapCardinality(tests)) = any(decided)
      AND sumIf(bitmapCardinality(tests), decision = 'skipped') > 0
    FROM #{decisions_sql()}
    """
    |> Snapshots.query!(%{project_id: project_id, run_id: run_id})
    |> then(fn [[skipped]] -> skipped in [true, 1] end)
  end

  defp decisions_sql do
    """
    test_impact_run_decisions FINAL WHERE project_id = {project_id:Int64} AND test_impact_run_id = {run_id:UUID}
    """
  end

  @doc """
  Where the units' lines are read from: one group per snapshot, nearest
  source first, with the units' tests as ranges of their numbers
  (`Snapshots.idx_chunks/1`), the modules whose processes' lines carry and
  the source the group's lines come from. Small whatever the number of
  tests, so a commit's reported coverage keeps it and reads one file's
  carried lines from it later (`lines_sql/3`).
  """
  def plan(units) do
    units
    |> Enum.group_by(& &1.snapshot_id)
    |> Enum.sort_by(fn {_snapshot_id, [unit | _]} -> source_rank(unit.source) end)
    |> Enum.map(fn {snapshot_id, [unit | _] = snapshot_units} ->
      %{
        snapshot_id: snapshot_id,
        checkpoint_id: checkpoint_id(snapshot_units),
        idx: snapshot_units |> Enum.flat_map(& &1.lines.idx) |> Snapshots.idx_chunks(),
        targets: snapshot_units |> Enum.flat_map(& &1.lines.targets) |> Enum.uniq(),
        source: unit.source
      }
    end)
  end

  @doc """
  SQL selecting the lines a plan (`plan/1`) carries, and its parameters: a
  row per file and group, `path`, `lines` (sorted), `rank` (the group's
  position in the plan, nearest first) and `source_run` (the run the
  group's lines come from), for the files that count: not test code in the
  snapshot, and not matching `excluded:` (a `Tuist.Tests.Coverage.ExcludedPaths`
  pattern). `paths:` narrows it to those files. The lines are merged and
  expanded in ClickHouse, so a caller joins them with the runs' rows there
  instead of reading every file's lines.
  """
  def lines_sql(project_id, plan, opts \\ []) do
    paths = Keyword.get(opts, :paths)

    {branches, params} =
      plan
      |> Enum.with_index()
      |> Enum.flat_map(fn {group, rank} ->
        chunks = if group.idx == [], do: [[]], else: group.idx
        chunks |> Enum.with_index() |> Enum.map(fn {chunk, i} -> {group, rank, chunk, i} end)
      end)
      |> Enum.map_reduce(%{project_id: project_id}, fn {group, rank, chunk, i}, params ->
        key = "#{rank}_#{i}"

        params =
          Map.merge(params, %{
            "snapshot_id_#{key}" => group.snapshot_id,
            "checkpoint_id_#{key}" => group.checkpoint_id,
            "idx_#{key}" => chunk,
            # Modules are read once, with the group's first chunk of tests.
            "targets_#{key}" => if(i == 0, do: group.targets, else: []),
            "source_run_#{key}" => group.source.run_id || ""
          })

        {lines_branch_sql(key, rank, not is_nil(paths)), params}
      end)

    params = if paths, do: Map.put(params, :paths, paths), else: params

    {filter, params} =
      case Keyword.get(opts, :excluded) do
        nil -> {"", params}
        excluded -> {"WHERE NOT match(path, {excluded:String})", Map.put(params, :excluded, excluded)}
      end

    union = Enum.map_join(branches, "\nUNION ALL\n", &"SELECT path, lines, rank, source_run FROM (#{&1})")
    {"SELECT path, lines, rank, source_run FROM (#{union}) #{filter}", params}
  end

  # One group's chunk of tests: the snapshot's lines of those tests, their
  # suites' setups and the group's modules, merged per file. The tests go as
  # ranges of their numbers, contiguous per suite and module, and ClickHouse
  # expands them back and finds their suites' and the modules' numbers
  # (`Snapshots.scope_keys_sql/0`).
  defp lines_branch_sql(key, rank, paths?) do
    scope_keys =
      Snapshots.scope_keys_sql()
      |> String.replace("{snapshot_id:UUID}", "{snapshot_id_#{key}:UUID}")
      |> String.replace("{checkpoint_id:UUID}", "{checkpoint_id_#{key}:UUID}")

    paths_filter = if paths?, do: "AND (epoch, path_id) IN (SELECT epoch, path_id FROM line_paths)", else: ""
    test_paths_filter = if paths?, do: "AND path IN {paths:Array(String)}", else: ""

    """
    WITH carried AS (#{Snapshots.idx_sql("idx_#{key}")}),
    #{scope_keys},
    refs AS (
      SELECT epoch, line_set FROM test_impact_snapshot_lines
      WHERE project_id = {project_id:Int64} AND snapshot_id = {snapshot_id_#{key}:UUID}
        AND ((scope = 'test' AND test_idx IN carried)
        OR (scope = 'suite' AND test_idx IN (
          SELECT test_idx FROM suite_keys WHERE (module_name, suite_name) IN (
            SELECT module_name, suite_name FROM numbering WHERE test_idx IN carried
          )
        ))
        OR (scope = 'target' AND test_idx IN (
          SELECT test_idx FROM module_keys WHERE module_name IN {targets_#{key}:Array(String)}
        )))
    ),
    -- A snapshot's sets are its run's week's (one week per snapshot), read
    -- once instead of from refs, which reads the snapshot's tests again.
    epochs AS (
      SELECT epoch FROM test_impact_snapshot_lines
      WHERE project_id = {project_id:Int64} AND snapshot_id = {snapshot_id_#{key}:UUID}
      LIMIT 1
    ),
    #{Snapshots.set_patterns_sql(paths?)}
    SELECT p.path AS path, l.lines AS lines, toUInt32(#{rank}) AS rank, {source_run_#{key}:String} AS source_run FROM (
      -- The sets share most patterns, so each is read once, and a file's
      -- are merged by expanding their ranges.
      SELECT epoch, path_id, CAST(arraySort(arrayDistinct(arrayFlatten(arrayMap((first, last) -> range(first, last + 1),
        arrayFilter((x, i) -> i % 2 = 1, ranges, arrayEnumerate(ranges)),
        arrayFilter((x, i) -> i % 2 = 0, ranges, arrayEnumerate(ranges)))))) AS Array(UInt32)) AS lines
      FROM (
        SELECT epoch, path_id, groupArrayArray(line_ranges) AS ranges FROM test_impact_line_patterns
        WHERE project_id = {project_id:Int64} AND epoch IN (SELECT epoch FROM epochs)
          AND (epoch, pattern) IN (SELECT epoch, pattern FROM set_patterns)
          #{paths_filter}
        GROUP BY epoch, path_id
      )
    ) AS l
    INNER JOIN line_paths AS p ON p.epoch = l.epoch AND p.path_id = l.path_id
    WHERE p.path NOT IN (
        SELECT path FROM test_impact_snapshot_files
        WHERE project_id = {project_id:Int64} AND snapshot_id = {snapshot_id_#{key}:UUID} AND is_test
          #{test_paths_filter}
      )
    """
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
    now = DateTime.utc_now()
    live = fn snapshot -> snapshot && DateTime.after?(snapshot.expires_at, now) && snapshot end

    # Once the snapshot a target was measured in has expired, a checkpoint
    # that copied it under the same hash still holds its rows.
    copies =
      Snapshots.carried_copies(
        context.project.id,
        context.repository_id,
        context.sha,
        for({module, source} <- sources, !live.(snapshots[source.run_id]), do: {module, hashes[module]})
      )

    units =
      for {module, tests} <- by_module,
          source = sources[module],
          snapshot = live.(snapshots[source.run_id]) || copies[{module, hashes[module]}] || snapshots[source.run_id],
          snapshot != nil do
        %{
          kind: :target,
          key: {:module, module},
          module: module,
          hash: hashes[module],
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
    # The hash is trusted for every build input, so no tracked file is compared.
    {kept, reasons} = guard(units, context, fn _sha -> :ok end)
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

  defp test_units([], _context, _target_reasons), do: {[], %{}}

  # The commit changed a tracked file and only targets skipped by their hash
  # carry: every test's evidence predates the change, so none is read, and a test is a gap
  # for its target's reason, or for the change.
  defp test_units(tests, %{only_hashed: true}, target_reasons) do
    {[],
     for(
       test <- tests,
       !Map.has_key?(target_reasons, {:module, test.module_name}),
       into: %{},
       do: {test.test_case_id, :tracked_file_changed}
     )}
  end

  # A test coverage-based test selection skipped carries from the snapshot
  # whose evidence decided it (`decided_units/2`): the decision already
  # proved its files unchanged against the checkout. Only the other tests
  # are evaluated against the baseline and the overlays.
  defp test_units(tests, context, _target_reasons) do
    {decided, tests} = decided_units(tests, context)
    {decided, decided_reasons} = guard(decided, context, fn _sha -> :ok end)
    {kept, reasons} = evaluated_units(tests, context)
    {decided ++ kept, Map.merge(reasons, decided_reasons)}
  end

  defp evaluated_units([], _context), do: {[], %{}}

  defp evaluated_units(tests, context) do
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

    {kept, guard_reasons} = guard(units, context, context.validity)
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

  # The baseline's checkpoints, nearest first: one per scheme and platform
  # the commit's runs ran.
  defp candidates(context) do
    context.baseline
    |> Enum.uniq_by(& &1.checkpoint.id)
    |> Enum.sort_by(& &1.depth)
    |> Enum.map(fn run ->
      {%{checkpoint: run.checkpoint}, %{checkpoint: checkpoint_source(run.checkpoint, run.depth)}}
    end)
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
    then = Map.merge(copied_blobs(context, layers.checkpoint, then), then)
    missing = then |> Map.keys() |> Enum.reject(&Map.has_key?(context.blobs, &1))
    now = Map.merge(context.blobs_now.(missing), context.blobs)
    for {path, blob} <- then, now[path] != blob, do: path
  end

  # The blobs of a checkpoint's files its runs didn't report: those of the
  # targets it copied from an earlier snapshot (`carried_targets`), which
  # its runs never executed. Their hash was the same at its commit, so their
  # files are read at that commit.
  defp copied_blobs(_context, %Snapshot{carried_targets: []}, _reported), do: %{}

  defp copied_blobs(context, checkpoint, reported) do
    missing =
      """
      SELECT DISTINCT path FROM test_impact_snapshot_files
      WHERE project_id = {project_id:Int64} AND snapshot_id = {snapshot_id:UUID}
      """
      |> Snapshots.query!(%{project_id: context.project.id, snapshot_id: checkpoint.id})
      |> Enum.map(&hd/1)
      |> Enum.reject(&Map.has_key?(reported, &1))

    context.blobs_then.(checkpoint.commit_sha, missing)
  end

  # Decided tests

  # The units of the tests the commit's impact runs skipped
  # (`skipped_tests/2`), taken from the snapshot whose evidence decided each,
  # and the tests left to evaluate: those without a decision, and those
  # whose deciding snapshot has expired, which a fold long after the run
  # reads as before. A test decided by the primary checkpoint has its number
  # there. One decided by an overlay has its row in the overlay when the
  # overlay replaces it, numbered as the overlay's checkpoint numbers its
  # tests, which needn't be the primary, or else in that checkpoint, so it's
  # found there by its test case id.
  defp decided_units(tests, context) do
    {decided, rest} = Enum.split_with(tests, &Map.has_key?(&1, :decision))

    snapshots =
      live_snapshots(Enum.flat_map(decided, fn %{decision: {primary, evidence, _idx}} -> [primary, evidence] end))

    units =
      decided
      |> Enum.group_by(fn %{decision: {primary, evidence, _idx}} -> {primary, evidence} end)
      |> Enum.flat_map(fn {{primary, evidence}, group} ->
        if snapshots[primary] && snapshots[evidence], do: decided_group(context, snapshots[evidence], group), else: []
      end)

    carried = MapSet.new(units, & &1.key)
    {units, rest ++ for(test <- decided, !MapSet.member?(carried, test.test_case_id), do: Map.delete(test, :decision))}
  end

  defp decided_group(context, %Snapshot{kind: :checkpoint} = checkpoint, group) do
    source = checkpoint_source(checkpoint, depth(context, checkpoint))

    Enum.map(group, fn %{decision: {_primary, _evidence, idx}} = test ->
      decided_unit(test, checkpoint, nil, idx, source)
    end)
  end

  defp decided_group(context, %Snapshot{kind: :overlay} = overlay, group) do
    run_id = List.first(overlay.test_run_ids)

    with %Snapshot{} = checkpoint <- live_snapshots([overlay.checkpoint_id])[overlay.checkpoint_id],
         {:ok, run} <- Tests.get_test(run_id) do
      overlay_source = %{sha: run.git_commit_sha, depth: nil, ran_at: overlay.ran_at, run_id: run_id}
      checkpoint_source = checkpoint_source(checkpoint, depth(context, checkpoint))
      rows = layered_rows(context.project.id, overlay, checkpoint, Enum.map(group, & &1.test_case_id))

      for test <- group, row = rows[test.test_case_id], row != nil do
        case row do
          {:overlay, idx} -> decided_unit(test, overlay, checkpoint.id, idx, overlay_source)
          {:checkpoint, idx} -> decided_unit(test, checkpoint, nil, idx, checkpoint_source)
        end
      end
    else
      _ -> []
    end
  end

  defp decided_unit(test, snapshot, checkpoint_id, idx, source) do
    %{
      kind: :test,
      key: test.test_case_id,
      module: test.module_name,
      tests: [Map.delete(test, :decision)],
      snapshot_id: snapshot.id,
      checkpoint_id: checkpoint_id,
      lines: %{
        targets: [],
        suites: if(test.suite_name == "", do: [], else: [{test.module_name, test.suite_name}]),
        idx: [idx]
      },
      run_id: source.run_id,
      source: source
    }
  end

  # Where each test has its row in an overlay's layers, by test case id: the
  # overlay's own when it holds evidence, else its checkpoint's.
  defp layered_rows(project_id, overlay, checkpoint, test_case_ids) do
    test_case_ids
    |> Enum.chunk_every(5_000)
    |> Enum.flat_map(fn ids ->
      Snapshots.query!(
        """
        SELECT toString(test_case_id), snapshot_id = {overlay_id:UUID}, test_idx
        FROM test_impact_snapshot_tests FINAL
        WHERE project_id = {project_id:Int64} AND snapshot_id IN ({overlay_id:UUID}, {checkpoint_id:UUID})
          AND test_case_id IN {ids:Array(UUID)} AND status NOT IN ('no_evidence', 'stale')
        """,
        %{project_id: project_id, overlay_id: overlay.id, checkpoint_id: checkpoint.id, ids: ids}
      )
    end)
    |> Enum.map(fn [id, in_overlay, idx] -> {id, in_overlay in [true, 1], idx} end)
    # The overlay's row wins: it's read last.
    |> Enum.sort_by(&elem(&1, 1))
    |> Map.new(fn {id, in_overlay, idx} -> {id, if(in_overlay, do: {:overlay, idx}, else: {:checkpoint, idx})} end)
  end

  defp live_snapshots(ids) do
    ids = ids |> Enum.uniq() |> Enum.reject(&is_nil/1)

    from(s in Snapshot, where: s.id in ^ids and s.expires_at > ^DateTime.utc_now())
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
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
  # the commit's as far as `validity` compares them, and its evidence holds
  # lines for every file that counts.
  defp guard([], _context, _validity), do: {[], %{}}

  defp guard(units, context, validity) do
    validity = units |> Enum.map(& &1.source.sha) |> Enum.uniq() |> Map.new(&{&1, validity.(&1)})
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
