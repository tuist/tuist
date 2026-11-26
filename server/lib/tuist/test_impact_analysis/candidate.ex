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
  5. `unaffected`: skipped.

  A changed file no evidence includes selects nothing: unless a tracked
  pattern matches it, which the diff check catches before (see
  `Tuist.TestImpactAnalysis.TrackedFiles`), no test is known to execute it.
  """
  alias Tuist.TestImpactAnalysis.Snapshots

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
  matched_path, executed_changed}`, against `changed_files` (`%{path}`).
  `matched_path` is the changed file that decided a test selected by
  `test_file_changed` or `impacted`, the first in path order, nil
  otherwise; `executed_changed` when a file the test or its suite's setup
  executed changed, which is what coverage carry checks, whichever rule
  decided it first.
  """
  def evaluate(project_id, %{checkpoint: checkpoint} = layers, changed_files, modules \\ nil, opts \\ []) do
    overlay = Map.get(layers, :overlay)
    tests = tests(project_id, checkpoint, overlay, modules)
    overridden = for {idx, %{layer: :overlay}} <- tests, into: MapSet.new(), do: idx
    hits = hits(project_id, checkpoint, overlay, changed_files, Keyword.get(opts, :matched_paths, false))
    checkpoint_hits = Map.get(hits, checkpoint.id, empty_hits())
    overlay_hits = if overlay, do: Map.get(hits, overlay.id, empty_hits()), else: empty_hits()

    # An overridden test's own files are the overlay's.
    merged =
      Map.new([:direct, :target, :suites], fn key ->
        {key, checkpoint_hits |> Map.fetch!(key) |> Map.drop(MapSet.to_list(overridden)) |> Map.merge(overlay_hits[key])}
      end)

    tests
    |> Map.values()
    |> Enum.map(fn test ->
      {reason, matched_path} = reason(test, merged)
      matched_path = if matched_path == "", do: nil, else: matched_path

      Map.merge(test, %{
        reason: reason,
        matched_path: matched_path,
        executed_changed: Map.has_key?(merged.direct, test.idx)
      })
    end)
    |> Enum.sort_by(& &1.idx)
  end

  @doc """
  When the evidence of one of `evaluate/4`'s tests ran: its overlay's run
  for a test the overlay replaces, its checkpoint's otherwise.
  """
  def evidence_ran_at(%{overlay: %{} = overlay}, %{layer: :overlay}), do: overlay.ran_at
  def evidence_ran_at(%{checkpoint: checkpoint}, _test), do: checkpoint.ran_at

  @doc "Whether the test's files didn't change: it's skipped, or selected only because it failed there."
  def unchanged?(%{reason: reason}), do: reason in [:unaffected, :failed_last_run]

  defp reason(test, hits) do
    direct = Map.get(hits.direct, test.idx)
    target = Map.get(hits.target, test.idx)

    cond do
      Map.has_key?(hits.suites, test.idx) -> {:test_file_changed, hits.suites[test.idx]}
      test.status in ["failed", "flaky"] and is_nil(direct) -> {:failed_last_run, nil}
      test.status in ["no_evidence", "stale"] -> {:no_evidence, nil}
      direct || target -> {:impacted, Enum.min(Enum.reject([direct, target], &is_nil/1))}
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
