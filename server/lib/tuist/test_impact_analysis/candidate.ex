defmodule Tuist.TestImpactAnalysis.Candidate do
  @moduledoc """
  The rules of coverage-based test selection applied to one snapshot
  (`Tuist.TestImpactAnalysis.Snapshots`) against the files that changed
  since its commit, read as bitmaps: a checkpoint, or an overlay over its
  checkpoint, where the overlay's tests replace the checkpoint's.

  Each test of the snapshot gets the reason of the first rule that decides
  it, in `Tuist.TestImpactAnalysis`'s order (the tracked-file check runs
  before, on the diff):

  1. `test_file_changed`: a changed test file belongs to its suite;
  2. `failed_last_run`: it failed or was flaky and none of the files it or its
     suite's setup executed changed, or it failed without evidence;
  3. `no_evidence`: it has no evidence of its own, or it's `stale`;
  4. `impacted`: a file it or its suite's setup executed changed, or one its
     module's processes executed outside every test;
  5. `owned_without_evidence`: a changed file no evidence of the snapshot
     includes affects its module;
  6. `unaffected`: skipped.
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.TestImpactAnalysis.Snapshots
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Test

  @files_sql """
  WITH files AS (
    SELECT snapshot_id, path, is_test, tests, target_tests, suite_tests
    FROM test_impact_snapshot_files
    WHERE project_id = {project_id:Int64} AND snapshot_id IN {ids:Array(UUID)} AND path IN {paths:Array(String)}
  )
  """

  # Each path keeps the tests of its bitmaps no earlier path in path order
  # holds: a running union in a window, so no test is expanded into a row
  # (at 5,000 paths, 20 of them run by all 200,000 tests, 54 ms and 103 MiB
  # against 627 ms and 470 MiB grouping a row per test and path).
  @matched_sql @files_sql <>
                 """
                 , kinds AS (
                   SELECT snapshot_id, path, 'direct' AS kind, tests AS bitmap FROM files
                   WHERE bitmapCardinality(tests) > 0
                   UNION ALL
                   SELECT snapshot_id, path, 'target', target_tests FROM files
                   WHERE bitmapCardinality(target_tests) > 0
                   UNION ALL
                   SELECT snapshot_id, path, 'suites', suite_tests FROM files
                   WHERE is_test AND bitmapCardinality(suite_tests) > 0
                 )
                 SELECT toString(snapshot_id), kind, path, bitmapToArray(fresh)
                 FROM (
                   SELECT snapshot_id, kind, path,
                     bitmapAndnot(bitmap, groupBitmapOrState(bitmap) OVER (PARTITION BY snapshot_id, kind ORDER BY path
                       ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)) AS fresh
                   FROM kinds
                 )
                 WHERE bitmapCardinality(fresh) > 0
                 """

  @union_sql @files_sql <>
               """
               SELECT toString(snapshot_id), kind, '', bitmapToArray(groupBitmapOrState(bitmap))
               FROM (
                 SELECT snapshot_id, 'direct' AS kind, tests AS bitmap FROM files
                 UNION ALL
                 SELECT snapshot_id, 'target', target_tests FROM files
                 UNION ALL
                 SELECT snapshot_id, 'suites', suite_tests FROM files WHERE is_test
               )
               GROUP BY snapshot_id, kind
               """

  @doc """
  The snapshot's tests, in `modules` when given, each as `%{idx,
  test_case_id, module_name, suite_name, status, layer, reason,
  matched_path, executed_changed, owned}`, against `changed_files` (`%{path,
  affected_modules}`). `matched_path` is the changed file that decided a
  test selected by `test_file_changed`, `impacted` or
  `owned_without_evidence`, the first in path order, nil otherwise;
  `executed_changed` when a file the test or its
  suite's setup executed changed, which is what coverage carry checks, and
  `owned` when a changed file no evidence includes affects its module,
  whichever rule decided it first.
  """
  def evaluate(project_id, %{checkpoint: checkpoint} = layers, changed_files, modules \\ nil, opts \\ []) do
    overlay = Map.get(layers, :overlay)
    instrumented? = Keyword.get(opts, :instrumented, false) and is_nil(overlay)
    tests = tests(project_id, checkpoint, overlay, if(instrumented?, do: nil, else: modules))

    instrumented = instrumented_paths(project_id, checkpoint, changed_files, tests, modules, instrumented?)

    tests = if modules, do: Map.filter(tests, fn {_idx, test} -> test.module_name in modules end), else: tests
    overridden = for {idx, %{layer: :overlay}} <- tests, into: MapSet.new(), do: idx
    hits = hits(project_id, checkpoint, overlay, changed_files, Keyword.get(opts, :matched_paths, false))
    checkpoint_hits = Map.get(hits, checkpoint.id, empty_hits())
    overlay_hits = if overlay, do: Map.get(hits, overlay.id, empty_hits()), else: empty_hits()

    # An overridden test's own files are the overlay's.
    merged =
      Map.new([:direct, :target, :suites], fn key ->
        {key, checkpoint_hits |> Map.fetch!(key) |> Map.drop(MapSet.to_list(overridden)) |> Map.merge(overlay_hits[key])}
      end)

    evidenced = MapSet.union(checkpoint_hits.evidenced, overlay_hits.evidenced)

    # Each module a changed file no evidence includes affects, with the first
    # such file in path order.
    owned_modules =
      changed_files
      |> Enum.reject(&(MapSet.member?(evidenced, &1.path) or MapSet.member?(instrumented, &1.path)))
      |> Enum.sort_by(& &1.path, :desc)
      |> Enum.flat_map(fn file -> Enum.map(Map.get(file, :affected_modules) || [], &{&1, file.path}) end)
      |> Map.new()

    tests
    |> Map.values()
    |> Enum.map(fn test ->
      {reason, matched_path} = reason(test, merged, owned_modules)
      matched_path = if matched_path == "", do: nil, else: matched_path

      Map.merge(test, %{
        reason: reason,
        matched_path: matched_path,
        executed_changed: Map.has_key?(merged.direct, test.idx),
        owned: Map.has_key?(owned_modules, test.module_name)
      })
    end)
    |> Enum.sort_by(& &1.idx)
  end

  defp instrumented_paths(
         project_id,
         %{carried_targets: []} = checkpoint,
         changed_files,
         tests,
         [_module] = modules,
         true
       ) do
    if Enum.uniq(Enum.map(Map.values(tests), & &1.module_name)) == modules do
      instrumented_paths(project_id, checkpoint, changed_files)
    else
      MapSet.new()
    end
  end

  defp instrumented_paths(_project_id, _checkpoint, _changed_files, _tests, _modules, _instrumented), do: MapSet.new()

  # Only a single-target checkpoint can prove that its zero-hit product
  # files were instrumented for that target. Aggregate evidence from a
  # different target, a partial report or test code cannot justify a skip.
  # Keep the default bitmap-only read unchanged, and bound path parameters
  # just as hits/5 does. No line layouts are needed for this proof.
  defp instrumented_paths(project_id, checkpoint, changed_files) do
    reports = Coverage.report_files_for_runs(project_id, checkpoint.test_run_ids, lines: false)

    # Empty shard reports have no file-row marker. Another shard's report
    # can therefore make legacy totals look complete again. Until reports
    # have durable per-shard identity, no sharded run can prove a zero hit.
    unsharded_runs =
      from(t in Test,
        where: t.project_id == ^project_id and t.id in ^checkpoint.test_run_ids,
        group_by: t.id,
        having: fragment("countIf(isNotNull(?)) = 0", t.shard_plan_id),
        select: t.id
      )

    # Check the whole latest report cohort before narrowing by path: a
    # partial replacement can omit the changed file, or contain no rows.
    complete_reports =
      from(f in reports,
        group_by: f.test_run_id,
        having: fragment("countIf(?) = 0", f.partial),
        select: f.test_run_id
      )

    complete_runs =
      from(r in subquery(Coverage.run_totals_query(project_id)),
        where:
          r.test_run_id in ^checkpoint.test_run_ids and r.test_run_id in subquery(unsharded_runs) and
            r.test_run_id in subquery(complete_reports) and not r.partial,
        select: count()
      )

    changed_files
    |> Enum.filter(&(Map.get(&1, :status) == "M"))
    |> Enum.map(& &1.path)
    |> Enum.uniq()
    |> Snapshots.path_chunks()
    |> Enum.flat_map(fn paths ->
      ClickHouseRepo.all(
        from(f in reports,
          where: subquery(complete_runs) == ^length(checkpoint.test_run_ids) and f.path in ^paths,
          group_by: f.path,
          having:
            fragment(
              "countIf(? OR NOT ? OR ? OR ? = 0 OR ? > 0) = 0",
              f.partial,
              f.in_repository,
              f.is_test,
              f.executable_lines,
              f.covered_lines
            ),
          select: f.path
        )
      )
    end)
    |> MapSet.new()
  end

  @doc """
  When the evidence of one of `evaluate/4`'s tests ran: its overlay's run
  for a test the overlay replaces, its checkpoint's otherwise.
  """
  def evidence_ran_at(%{overlay: %{} = overlay}, %{layer: :overlay}), do: overlay.ran_at
  def evidence_ran_at(%{checkpoint: checkpoint}, _test), do: checkpoint.ran_at

  @doc "Whether the test's files didn't change: it's skipped, or selected only because it failed there."
  def unchanged?(%{reason: reason}), do: reason in [:unaffected, :failed_last_run]

  defp reason(test, hits, owned_modules) do
    direct = Map.get(hits.direct, test.idx)
    target = Map.get(hits.target, test.idx)

    cond do
      Map.has_key?(hits.suites, test.idx) -> {:test_file_changed, hits.suites[test.idx]}
      test.status in ["failed", "flaky"] and is_nil(direct) -> {:failed_last_run, nil}
      test.status in ["no_evidence", "stale"] -> {:no_evidence, nil}
      direct || target -> {:impacted, Enum.min(Enum.reject([direct, target], &is_nil/1))}
      Map.has_key?(owned_modules, test.module_name) -> {:owned_without_evidence, owned_modules[test.module_name]}
      true -> {:unaffected, nil}
    end
  end

  # The snapshot's tests by number, an overlay's row replacing its checkpoint's.
  defp tests(project_id, checkpoint, overlay, modules) do
    {module_filter, params} =
      case modules do
        nil -> {"", %{}}
        modules -> {"AND module_name IN {modules:Array(String)}", %{modules: modules}}
      end

    """
    SELECT toString(snapshot_id), test_idx, toString(test_case_id), module_name, suite_name, toString(status)
    FROM test_impact_snapshot_tests FINAL
    WHERE project_id = {project_id:Int64} AND snapshot_id IN {ids:Array(UUID)} #{module_filter}
    """
    |> Snapshots.query!(Map.merge(params, %{project_id: project_id, ids: ids(checkpoint, overlay)}))
    |> Enum.sort_by(fn [snapshot_id | _] -> snapshot_id != checkpoint.id end)
    |> Map.new(fn [snapshot_id, idx, test_case_id, module_name, suite_name, status] ->
      {idx,
       %{
         idx: idx,
         test_case_id: test_case_id,
         module_name: module_name,
         suite_name: suite_name,
         status: status,
         layer: if(snapshot_id == checkpoint.id, do: :checkpoint, else: :overlay)
       }}
    end)
  end

  # Per layer, the changed paths it has evidence of and the tests their
  # bitmaps hold: with `matched?`, as one bitmap per path of the tests no
  # earlier path holds; otherwise one union per layer, each test matched to
  # "". Chunks go in path order, so a test an earlier chunk matched keeps
  # that path.
  defp hits(project_id, checkpoint, overlay, changed_files, matched?) do
    changed_files
    |> Enum.map(& &1.path)
    |> Enum.uniq()
    |> Enum.sort()
    |> Snapshots.path_chunks()
    |> Enum.flat_map(fn paths ->
      params = %{project_id: project_id, ids: ids(checkpoint, overlay), paths: paths}

      evidenced =
        Snapshots.query!(
          """
          SELECT toString(snapshot_id), 'evidenced', groupUniqArray(path), []
          FROM test_impact_snapshot_files
          WHERE project_id = {project_id:Int64} AND snapshot_id IN {ids:Array(UUID)} AND path IN {paths:Array(String)}
          GROUP BY snapshot_id
          """,
          params
        )

      evidenced ++ Snapshots.query!(if(matched?, do: @matched_sql, else: @union_sql), params)
    end)
    |> Enum.reduce(%{}, fn
      [snapshot_id, "evidenced", paths, _idx], acc ->
        acc
        |> Map.put_new(snapshot_id, empty_hits())
        |> update_in([snapshot_id, :evidenced], &MapSet.union(&1, MapSet.new(paths)))

      [snapshot_id, kind, path, idx], acc ->
        key = String.to_existing_atom(kind)

        acc
        |> Map.put_new(snapshot_id, empty_hits())
        |> update_in([snapshot_id, key], fn matched -> Enum.reduce(idx, matched, &Map.put_new(&2, &1, path)) end)
    end)
  end

  defp empty_hits, do: %{evidenced: MapSet.new(), direct: %{}, target: %{}, suites: %{}}

  defp ids(checkpoint, nil), do: [checkpoint.id]
  defp ids(checkpoint, overlay), do: [checkpoint.id, overlay.id]
end
