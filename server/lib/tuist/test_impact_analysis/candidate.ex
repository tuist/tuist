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
  alias Tuist.TestImpactAnalysis.Snapshots

  @doc """
  The snapshot's tests, in `modules` when given, each as `%{idx,
  test_case_id, module_name, suite_name, status, layer, reason,
  executed_changed, owned}`, against `changed_files` (`%{path,
  affected_modules}`): `executed_changed` when a file the test or its
  suite's setup executed changed, which is what coverage carry checks, and
  `owned` when a changed file no evidence includes affects its module,
  whichever rule decided it first.
  """
  def evaluate(project_id, %{checkpoint: checkpoint} = layers, changed_files, modules \\ nil) do
    overlay = Map.get(layers, :overlay)
    tests = tests(project_id, checkpoint, overlay, modules)
    overridden = for {idx, %{layer: :overlay}} <- tests, into: MapSet.new(), do: idx
    hits = hits(project_id, checkpoint, overlay, changed_files)
    checkpoint_hits = Map.get(hits, checkpoint.id, empty_hits())
    overlay_hits = if overlay, do: Map.get(hits, overlay.id, empty_hits()), else: empty_hits()

    merged =
      Map.new([:direct, :target, :suites], fn key ->
        {key, checkpoint_hits |> Map.fetch!(key) |> MapSet.difference(overridden) |> MapSet.union(overlay_hits[key])}
      end)

    evidenced = MapSet.union(checkpoint_hits.evidenced, overlay_hits.evidenced)

    owned_modules =
      changed_files
      |> Enum.reject(&MapSet.member?(evidenced, &1.path))
      |> Enum.flat_map(&(Map.get(&1, :affected_modules) || []))
      |> MapSet.new()

    tests
    |> Map.values()
    |> Enum.map(fn test ->
      test
      |> Map.put(:reason, reason(test, merged, owned_modules))
      |> Map.put(:executed_changed, MapSet.member?(merged.direct, test.idx))
      |> Map.put(:owned, MapSet.member?(owned_modules, test.module_name))
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

  defp reason(test, hits, owned_modules) do
    cond do
      MapSet.member?(hits.suites, test.idx) -> :test_file_changed
      test.status in ["failed", "flaky"] and not MapSet.member?(hits.direct, test.idx) -> :failed_last_run
      test.status in ["no_evidence", "stale"] -> :no_evidence
      MapSet.member?(hits.direct, test.idx) or MapSet.member?(hits.target, test.idx) -> :impacted
      MapSet.member?(owned_modules, test.module_name) -> :owned_without_evidence
      true -> :unaffected
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

  # Per layer, the changed paths it has evidence of and the union of their
  # bitmaps, reduced in ClickHouse.
  defp hits(project_id, checkpoint, overlay, changed_files) do
    changed_files
    |> Enum.map(& &1.path)
    |> Enum.uniq()
    |> Snapshots.path_chunks()
    |> Enum.flat_map(fn paths ->
      Snapshots.query!(
        """
        SELECT toString(snapshot_id), groupUniqArray(path),
          bitmapToArray(groupBitmapOrState(tests)),
          bitmapToArray(groupBitmapOrState(target_tests)),
          bitmapToArray(groupBitmapOrState(if(is_test, suite_tests, bitmapBuild(emptyArrayUInt32()))))
        FROM test_impact_snapshot_files
        WHERE project_id = {project_id:Int64} AND snapshot_id IN {ids:Array(UUID)} AND path IN {paths:Array(String)}
        GROUP BY snapshot_id
        """,
        %{project_id: project_id, ids: ids(checkpoint, overlay), paths: paths}
      )
    end)
    |> Enum.reduce(%{}, fn [snapshot_id, paths, direct, target, suites], acc ->
      hits = %{
        evidenced: MapSet.new(paths),
        direct: MapSet.new(direct),
        target: MapSet.new(target),
        suites: MapSet.new(suites)
      }

      Map.update(acc, snapshot_id, hits, fn existing ->
        Map.merge(existing, hits, fn _key, a, b -> MapSet.union(a, b) end)
      end)
    end)
  end

  defp empty_hits, do: %{evidenced: MapSet.new(), direct: MapSet.new(), target: MapSet.new(), suites: MapSet.new()}

  defp ids(checkpoint, nil), do: [checkpoint.id]
  defp ids(checkpoint, overlay), do: [checkpoint.id, overlay.id]
end
