defmodule Tuist.TestImpactAnalysis.Decision do
  @moduledoc """
  Decides an impact run from snapshots (`Tuist.TestImpactAnalysis.Snapshots`):
  which of the baseline checkpoint's tests in the modules left to decide run
  and why, given the files that changed since the baseline.

  A changed tracked file decides nothing: every test runs
  (`tracked_path/2`). Otherwise two candidates decide each test, newest
  first:

  - the **baseline's checkpoint**, against the request's diff (the primary);
  - the **branch's newest overlay**, another commit's run on the same
    branch: on a pull request checked out as GitHub's merge commit, the
    previous push's merge checkout, which is never an ancestor. Its tree is
    its checkpoint's plus its diff, so what changed since it is composed
    from data the server holds: both diffs, and the file changes between
    the two checkpoints' commits when they differ
    (`Tuist.GitHistory.changed_files/4`). It's left out when any part is
    missing or truncated, or a tracked file changed.

  A skipped test of a module the client says gained a file (`A` with the
  module in `affected_modules`) keeps that file as its matched path, so the
  module's skip list names its tests rather than the module and a test the
  file adds runs.

  A test is decided by the candidate whose evidence of it ran last among
  those where its files are unchanged: skipped when it passed there,
  `failed_last_run` when it didn't; selected with the primary's reason and
  matched path when there's none. A test the branch's overlay doesn't
  replace has its checkpoint's evidence there, as old as that checkpoint. A
  changed test file's suites select through the primary's diff whatever the
  other candidate says.

  The decision is stored in `test_impact_run_decisions` (`store/4`), one
  bitmap per decision, reason, changed file that matched and snapshot whose
  evidence decided it, numbered as the primary checkpoint numbers its tests,
  and read back by `stored/2`.
  """
  alias Tuist.GitHistory
  alias Tuist.IngestRepo
  alias Tuist.Projects.Project
  alias Tuist.TestImpactAnalysis.Candidate
  alias Tuist.TestImpactAnalysis.Snapshot
  alias Tuist.TestImpactAnalysis.Snapshots
  alias Tuist.TestImpactAnalysis.Storage
  alias Tuist.TestImpactAnalysis.TrackedFiles

  @store_sql """
  INSERT INTO test_impact_run_decisions (project_id, test_impact_run_id, snapshot_id, evidence_snapshot_id,
    decision, reason, matched_path, chunk, tests, decided, inserted_at)
  SELECT {project_id:Int64}, {run_id:UUID}, {snapshot_id:UUID}, {evidence:Array(UUID)}[g], {decisions:Array(String)}[g],
    {reasons:Array(String)}[g], {paths:Array(String)}[g], {chunks:Array(UInt16)}[g],
    groupBitmapState(toUInt32(test_idx)), {decided:UInt32}, {inserted_at:DateTime64(6)}
  FROM (
    SELECT g, arrayJoin(arrayFlatten(arrayMap(i -> range({idx:Array(UInt32)}[2 * i - 1], {idx:Array(UInt32)}[2 * i] + 1),
      range({firsts:Array(UInt32)}[g], {lasts:Array(UInt32)}[g] + 1)))) AS test_idx
    FROM (SELECT arrayJoin(range(1, length({firsts:Array(UInt32)}) + 1)) AS g)
  )
  GROUP BY g
  """

  @doc """
  The first changed file, in path order, that is one of the project's
  tracked files (`Tuist.TestImpactAnalysis.TrackedFiles`: its build
  system's defaults plus the configured `patterns`): a change that can
  affect any test without showing in coverage. `%{path, pattern, default}`,
  or nil when none is.
  """
  def tracked_path(%Project{} = project, changed_files, patterns \\ []) do
    project |> TrackedFiles.matcher(patterns) |> TrackedFiles.first_match(changed_files)
  end

  @doc """
  Decides the tests of `checkpoint` in `request.requested_modules` against
  `changed_files` (`%{path, status, blob, affected_modules}`, the diff from
  the checkpoint's commit). `request` has the checked-out `commit_sha`, its
  `git_branch`, `scheme`, `platform`, and `before`, when the request
  arrived, which bounds the branch's overlays. Returns each test's `%{idx,
  test_case_id, module_name, suite_name, decision, reason, matched_path,
  snapshot_id}` by test case id.
  """
  def decide(_project, %{requested_modules: []}, _checkpoint, _changed_files), do: %{}

  def decide(%Project{} = project, request, %Snapshot{} = checkpoint, changed_files) do
    primary = %{
      layers: %{checkpoint: checkpoint, overlay: nil},
      snapshot: checkpoint,
      tests:
        project.id
        |> Candidate.evaluate(%{checkpoint: checkpoint}, changed_files, request.requested_modules, matched_paths: true)
        |> by_id()
    }

    # The primary first: it wins a tie, such as a row the branch's overlay
    # keeps from the same checkpoint.
    candidates = Enum.reject([primary, branch_candidate(project, request, checkpoint, changed_files)], &is_nil/1)
    primary |> combine(candidates) |> mark_added(changed_files)
  end

  # A skipped test of a module that gained a file keeps that file as its
  # matched path, so its module's skip list names its tests and never the
  # module: a test the added file defines, which no evidence knows yet, runs.
  defp mark_added(decisions, changed_files) do
    added =
      changed_files
      |> Enum.filter(&(&1.status == "A"))
      |> Enum.sort_by(& &1.path, :desc)
      |> Enum.flat_map(fn file -> Enum.map(Map.get(file, :affected_modules) || [], &{&1, file.path}) end)
      |> Map.new()

    if added == %{} do
      decisions
    else
      Map.new(decisions, fn
        {id, %{decision: :skipped, module_name: module} = test} when is_map_key(added, module) ->
          {id, %{test | matched_path: added[module]}}

        entry ->
          entry
      end)
    end
  end

  defp by_id(tests), do: Map.new(tests, &{&1.test_case_id, &1})

  defp combine(primary, candidates) do
    Map.new(primary.tests, fn {test_case_id, test} ->
      decided = if !final?(test), do: newest_unchanged(candidates, test_case_id)
      {reason, candidate} = decided || {test.reason, primary}
      matched_path = if candidate == primary, do: test.matched_path

      {test_case_id,
       %{
         idx: test.idx,
         test_case_id: test_case_id,
         module_name: test.module_name,
         suite_name: test.suite_name,
         decision: decision(reason),
         reason: reason,
         matched_path: matched_path,
         snapshot_id: evidence_id(candidate)
       }}
    end)
  end

  defp final?(test), do: test.reason == :test_file_changed

  defp newest_unchanged(candidates, test_case_id) do
    candidates
    |> Enum.flat_map(fn candidate ->
      with %{} = test <- Map.get(candidate.tests, test_case_id), true <- Candidate.unchanged?(test) do
        [{test.reason, candidate, Candidate.evidence_ran_at(candidate.layers, test)}]
      else
        _ -> []
      end
    end)
    |> Enum.max_by(&elem(&1, 2), DateTime, fn -> nil end)
    |> case do
      nil -> nil
      {reason, candidate, _ran_at} -> {reason, candidate}
    end
  end

  defp decision(:unaffected), do: :skipped
  defp decision(_reason), do: :selected

  defp evidence_id(%{layers: %{overlay: %Snapshot{id: id}}}), do: id
  defp evidence_id(%{layers: %{checkpoint: %Snapshot{id: id}}}), do: id

  # The branch's previous run, against what changed since its tree: its diff
  # from its checkpoint, the checkpoints' commits' file changes, and the
  # request's diff from the primary checkpoint, each path's blob compared
  # through whichever of them has it last.
  defp branch_candidate(project, request, checkpoint, changed_files) do
    with {overlay, previous_checkpoint} <-
           Snapshots.latest_branch_overlay(
             project.id,
             request.git_branch,
             %{scheme: request.scheme, platform: request.platform},
             request.commit_sha,
             request.before
           ),
         {:ok, previous_diff} <- whole_diff(project.id, overlay.commit_sha, overlay.base_sha),
         between when is_list(between) <- between(checkpoint.repository_id, previous_checkpoint, checkpoint) do
      composed = compose(previous_diff.changed_files, between, changed_files)

      if tracked_path(project, composed, Map.get(request, :tracked_files, [])) do
        nil
      else
        layers = %{checkpoint: previous_checkpoint, overlay: overlay}

        %{
          layers: layers,
          snapshot: overlay,
          tests: project.id |> Candidate.evaluate(layers, composed, request.requested_modules) |> by_id()
        }
      end
    else
      _ -> nil
    end
  end

  defp between(_repository_id, %Snapshot{commit_sha: sha}, %Snapshot{commit_sha: sha}), do: []

  defp between(repository_id, from, to) do
    case GitHistory.changed_files(repository_id, from.commit_sha, to.commit_sha) do
      files when is_list(files) -> files
      _unknown -> nil
    end
  end

  @doc """
  The files that differ between two trees given as diffs from their
  checkpoints, `previous` (`%{path, status, blob, affected_modules}`, from
  the checkpoint at `from`) and `current` (from the checkpoint at `to`),
  with `between` the files that differ between those checkpoints'
  commits (`%{path, from, to}`). A path none of them names has the same blob
  in both trees.
  """
  def compose(previous, between, current) do
    previous_blobs = Map.new(previous, &{&1.path, diff_blob(&1)})
    current_blobs = Map.new(current, &{&1.path, diff_blob(&1)})
    between = Map.new(between, &{&1.path, &1})
    modules = Map.new(previous ++ current, &{&1.path, Map.get(&1, :affected_modules)})

    (Map.keys(previous_blobs) ++ Map.keys(current_blobs) ++ Map.keys(between))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.flat_map(fn path ->
      # Through `between` when a diff doesn't name the path: the previous tree
      # holds its blob at `from`, the current one at `to`.
      before = Map.get_lazy(previous_blobs, path, fn -> between_blob(between, path, :from) end)
      now = Map.get_lazy(current_blobs, path, fn -> between_blob(between, path, :to) end)

      if before == now do
        []
      else
        [
          %{
            path: path,
            status: if(is_nil(now), do: "D", else: "M"),
            blob: if(is_binary(now), do: now),
            affected_modules: modules[path]
          }
        ]
      end
    end)
  end

  defp diff_blob(%{status: "D"}), do: nil
  defp diff_blob(%{blob: blob}) when blob in [nil, ""], do: {:unknown, make_ref()}
  defp diff_blob(%{blob: blob}), do: blob

  # Without a row in `between`, both checkpoints' commits hold the same blob,
  # which neither diff names: equal on both sides.
  defp between_blob(between, path, side) do
    case Map.get(between, path) do
      nil -> :unchanged_since_checkpoints
      row -> Map.fetch!(row, side)
    end
  end

  defp whole_diff(project_id, commit_sha, baseline_sha) do
    case Storage.get_diff(project_id, commit_sha, baseline_sha) do
      {:ok, diff} when diff.changed_files_count == length(diff.changed_files) -> {:ok, diff}
      {:ok, _truncated} -> {:error, :diff_truncated}
      {:error, _reason} -> {:error, :diff_unavailable}
    end
  end

  @doc """
  Stores `decide/4`'s decisions for the impact run `run_id`, numbered as
  `checkpoint` numbers its tests. Each group of tests sharing a decision,
  reason, matched path and deciding snapshot is one bitmap, written as
  ranges in `chunk`s under ClickHouse's limit on a parameter, and many
  groups go in one statement. Every row holds how many tests the whole
  decision has (`decided`), so a decision written in part reads as none.
  """
  def store(_project_id, _run_id, _checkpoint, decisions) when decisions == %{}, do: :ok

  def store(project_id, run_id, %Snapshot{} = checkpoint, decisions) do
    params = %{
      project_id: project_id,
      run_id: run_id,
      snapshot_id: checkpoint.id,
      decided: map_size(decisions),
      inserted_at: NaiveDateTime.utc_now()
    }

    decisions
    |> Map.values()
    |> Enum.group_by(&{&1.decision, &1.reason, &1.snapshot_id, &1.matched_path || ""}, & &1.idx)
    |> Enum.sort()
    |> Enum.flat_map(fn {key, idx} ->
      idx |> Snapshots.idx_chunks() |> Enum.with_index() |> Enum.map(fn {ranges, chunk} -> {key, chunk, ranges} end)
    end)
    |> batches()
    |> Enum.each(fn groups -> IngestRepo.query!(@store_sql, Map.merge(params, batch_params(groups))) end)
  end

  # Groups per statement: their ranges and matched paths each within a
  # parameter's limit (a path counted as if every byte were URL-encoded).
  @batch_ints 10_000
  @batch_path_bytes 100_000

  defp batches(groups) do
    Enum.chunk_while(
      groups,
      {[], 0, 0},
      fn {{_d, _r, _s, path}, _chunk, ranges} = group, {batch, ints, bytes} ->
        {group_ints, group_bytes} = {length(ranges), byte_size(path) * 3 + 9}

        if batch != [] and (ints + group_ints > @batch_ints or bytes + group_bytes > @batch_path_bytes),
          do: {:cont, Enum.reverse(batch), {[group], group_ints, group_bytes}},
          else: {:cont, {[group | batch], ints + group_ints, bytes + group_bytes}}
      end,
      fn
        {[], _ints, _bytes} -> {:cont, {[], 0, 0}}
        {batch, _ints, _bytes} -> {:cont, Enum.reverse(batch), {[], 0, 0}}
      end
    )
  end

  # Group `g`'s ranges are pairs `first[g]..last[g]` of the flat `idx`.
  defp batch_params(groups) do
    {firsts, lasts, _next} =
      Enum.reduce(groups, {[], [], 1}, fn {_key, _chunk, ranges}, {firsts, lasts, next} ->
        pairs = div(length(ranges), 2)
        {[next | firsts], [next + pairs - 1 | lasts], next + pairs}
      end)

    %{
      idx: Enum.flat_map(groups, &elem(&1, 2)),
      firsts: Enum.reverse(firsts),
      lasts: Enum.reverse(lasts),
      decisions: Enum.map(groups, fn {{decision, _r, _s, _p}, _c, _i} -> to_string(decision) end),
      reasons: Enum.map(groups, fn {{_d, reason, _s, _p}, _c, _i} -> to_string(reason) end),
      evidence: Enum.map(groups, fn {{_d, _r, snapshot_id, _p}, _c, _i} -> snapshot_id end),
      paths: Enum.map(groups, fn {{_d, _r, _s, path}, _c, _i} -> path end),
      chunks: Enum.map(groups, &elem(&1, 1))
    }
  end

  @doc """
  The impact run's stored decision: `%{snapshot_id, tests}`, the primary
  checkpoint and each test as `%{idx, test_case_id, module_name,
  suite_name, decision, reason, matched_path, evidence_snapshot_id}`
  (`matched_path` nil when no file decided it); nil when the run has no
  complete decision.
  """
  def stored(project_id, run_id) do
    params = %{project_id: project_id, run_id: run_id}

    decisions = """
    test_impact_run_decisions FINAL WHERE project_id = {project_id:Int64} AND test_impact_run_id = {run_id:UUID}
    """

    case Snapshots.query!(
           """
           SELECT toString(any(snapshot_id)) FROM #{decisions}
           HAVING count() > 0 AND sum(bitmapCardinality(tests)) = any(decided)
           """,
           params
         ) do
      [[snapshot_id]] ->
        tests =
          """
          SELECT d.test_idx, toString(t.test_case_id), t.module_name, t.suite_name, d.decision, d.reason,
            d.matched_path, toString(d.evidence_snapshot_id)
          FROM (
            SELECT toString(decision) AS decision, reason, matched_path, evidence_snapshot_id,
              arrayJoin(bitmapToArray(tests)) AS test_idx
            FROM #{decisions}
          ) AS d
          INNER JOIN (
            SELECT test_idx, test_case_id, module_name, suite_name FROM test_impact_snapshot_tests FINAL
            WHERE project_id = {project_id:Int64} AND snapshot_id = {snapshot_id:UUID}
          ) AS t ON t.test_idx = d.test_idx
          """
          |> Snapshots.query!(Map.put(params, :snapshot_id, snapshot_id))
          |> Enum.map(fn [idx, test_case_id, module_name, suite_name, decision, reason, matched_path, evidence] ->
            %{
              idx: idx,
              test_case_id: test_case_id,
              module_name: module_name,
              suite_name: suite_name,
              decision: String.to_existing_atom(decision),
              reason: String.to_existing_atom(reason),
              matched_path: if(matched_path != "", do: matched_path),
              evidence_snapshot_id: evidence
            }
          end)

        %{snapshot_id: snapshot_id, tests: tests}

      [] ->
        nil
    end
  end

  @doc "How many tests `checkpoint` holds in each of `modules`, as `%{module => count}`, 0 for one it doesn't."
  def module_counts(_project_id, _checkpoint, []), do: %{}

  def module_counts(project_id, %Snapshot{} = checkpoint, modules) do
    counts =
      """
      SELECT module_name, count() FROM test_impact_snapshot_tests FINAL
      WHERE project_id = {project_id:Int64} AND snapshot_id = {snapshot_id:UUID} AND module_name IN {modules:Array(String)}
      GROUP BY module_name
      """
      |> Snapshots.query!(%{project_id: project_id, snapshot_id: checkpoint.id, modules: modules})
      |> Map.new(fn [module, count] -> {module, count} end)

    Map.new(modules, &{&1, Map.get(counts, &1, 0)})
  end
end
