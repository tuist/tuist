defmodule Tuist.TestImpactAnalysis.Shadow do
  @moduledoc """
  Decides an impact run again from snapshots (`Tuist.TestImpactAnalysis.Snapshots`),
  beside the decision the runs request made from per-test versions. Nothing
  calls it in production yet: the runs request is to serve this decision
  in place of the versions' once the snapshots are backfilled.

  Two candidates decide each test, newest first:

  - the **baseline's checkpoint**, against the request's diff (the primary);
  - the **branch's newest overlay**, another commit's run on the same
    branch: on a pull request checked out as GitHub's merge commit, the
    previous push's merge checkout, which is never an ancestor. Its tree is
    its checkpoint's plus its diff, so what changed since it is composed
    from data the server holds: both diffs, and the file changes between
    the two checkpoints' commits when they differ
    (`Tuist.GitHistory.changed_files/4`). It's left out when any part is
    missing or truncated, or a tracked file changed.

  A test is decided by the candidate whose evidence of it ran last among
  those where its files are unchanged: skipped when it passed there,
  `failed_last_run` when it didn't; selected with the primary's reason when
  there's none. A test the branch's overlay doesn't replace has its
  checkpoint's evidence there, as old as that checkpoint. A changed test
  file's suites and the tests of a module a changed file no evidence
  includes affects select through the primary's diff whatever the other
  candidate says, as they do today.

  The decision is stored in `test_impact_run_decisions`, one bitmap per
  decision, reason and the snapshot whose evidence decided it, numbered as
  the primary checkpoint numbers its tests.
  """
  alias Tuist.GitHistory
  alias Tuist.IngestRepo
  alias Tuist.Projects.Project
  alias Tuist.TestImpactAnalysis.Candidate
  alias Tuist.TestImpactAnalysis.Input
  alias Tuist.TestImpactAnalysis.Run
  alias Tuist.TestImpactAnalysis.Snapshot
  alias Tuist.TestImpactAnalysis.Snapshots
  alias Tuist.TestImpactAnalysis.Storage

  require Logger

  @final_reasons [:test_file_changed, :owned_without_evidence]

  @doc """
  Decides the impact run from snapshots, stores the decision and returns
  `{:ok, %{decisions:, candidates:, comparison:}}`: each test's
  `%{decision:, reason:, snapshot_id:}` by test case id, the candidates'
  snapshot ids, and how it compares with the run's stored selection
  (`only_shadow_skipped` and `only_run_skipped`, test case ids).
  `{:error, reason}` when it can't decide: the run isn't a selection, its
  diff isn't stored or is truncated, or its baseline has no checkpoint. A
  run hashing left no module to decide stores no diff and has nothing to
  decide.
  """
  def decide(%Project{}, %Run{outcome: "selected", requested_modules: []}),
    do: {:ok, %{decisions: %{}, candidates: [], comparison: %{only_shadow_skipped: [], only_run_skipped: []}}}

  def decide(%Project{} = project, %Run{outcome: "selected"} = run) do
    scope = %{scheme: run.build_context["scheme"], platform: run.platform}

    with {:ok, diff} <- whole_diff(project.id, run.commit_sha, run.baseline_sha),
         %Snapshot{} = checkpoint <-
           Snapshots.checkpoint(project.id, run.baseline_sha, scope.scheme, scope.platform) || {:error, :no_checkpoint} do
      primary = %{
        layers: %{checkpoint: checkpoint, overlay: nil},
        snapshot: checkpoint,
        tests:
          project.id
          |> Candidate.evaluate(%{checkpoint: checkpoint}, diff.changed_files, run.requested_modules)
          |> by_id()
      }

      # The primary first: it wins a tie, such as a row the branch's overlay
      # keeps from the same checkpoint.
      candidates =
        Enum.reject([primary, branch_candidate(project, run, scope, checkpoint, diff.changed_files)], &is_nil/1)

      decisions = combine(primary, candidates)
      store(project.id, run.id, checkpoint, primary, decisions)
      comparison = compare(project.id, run.id, decisions)

      Logger.info(
        "Test impact shadow decision for #{run.id}: #{map_size(decisions)} tests, " <>
          "#{length(candidates)} candidates, #{length(comparison.only_shadow_skipped)} only shadow skipped, " <>
          "#{length(comparison.only_run_skipped)} only run skipped"
      )

      {:ok, %{decisions: decisions, candidates: Enum.map(candidates, & &1.snapshot.id), comparison: comparison}}
    end
  end

  def decide(_project, _run), do: {:error, :not_selected}

  defp by_id(tests), do: Map.new(tests, &{&1.test_case_id, &1})

  defp combine(primary, candidates) do
    Map.new(primary.tests, fn {test_case_id, test} ->
      decided = if !final?(test), do: newest_unchanged(candidates, test_case_id)
      {reason, candidate} = decided || {test.reason, primary}
      {test_case_id, %{idx: test.idx, decision: decision(reason), reason: reason, snapshot_id: evidence_id(candidate)}}
    end)
  end

  defp final?(test), do: test.reason in @final_reasons or test.owned

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
  defp branch_candidate(project, run, scope, checkpoint, changed_files) do
    with {overlay, previous_checkpoint} <-
           Snapshots.latest_branch_overlay(
             project.id,
             run.git_branch,
             scope,
             run.commit_sha,
             DateTime.from_naive!(run.inserted_at, "Etc/UTC")
           ),
         {:ok, previous_diff} <- whole_diff(project.id, overlay.commit_sha, overlay.base_sha),
         between when is_list(between) <- between(checkpoint.repository_id, previous_checkpoint, checkpoint) do
      composed = compose(previous_diff.changed_files, between, changed_files)
      tracked = Input.new(%{tracked_file_globs: GitHistory.settings(project).tracked_file_globs})

      if Enum.any?(composed, &Input.tracked?(tracked, &1.path)) do
        nil
      else
        layers = %{checkpoint: previous_checkpoint, overlay: overlay}

        %{
          layers: layers,
          snapshot: overlay,
          tests: project.id |> Candidate.evaluate(layers, composed, run.requested_modules) |> by_id()
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

  defp store(project_id, run_id, checkpoint, primary, decisions) do
    inserted_at = NaiveDateTime.utc_now()

    decisions
    |> Map.values()
    |> Enum.group_by(&{&1.decision, &1.reason, &1.snapshot_id}, & &1.idx)
    |> Enum.each(fn {{decision, reason, snapshot_id}, idx} ->
      # Numbers go as ranges, a chunk per row: a parameter holds at most
      # 128 KiB, and the key keeps chunks from replacing each other.
      idx
      |> Snapshots.idx_chunks()
      |> Enum.with_index()
      |> Enum.each(fn {chunk, i} ->
        IngestRepo.query!(
          """
          INSERT INTO test_impact_run_decisions (project_id, test_impact_run_id, snapshot_id, evidence_snapshot_id,
            decision, reason, chunk, tests, decided, inserted_at)
          SELECT {project_id:Int64}, {run_id:UUID}, {snapshot_id:UUID}, {evidence_snapshot_id:UUID}, {decision:String},
            {reason:String}, {chunk:UInt16}, groupBitmapState(toUInt32(test_idx)), {decided:UInt32},
            {inserted_at:DateTime64(6)}
          FROM (#{Snapshots.idx_sql()})
          """,
          %{
            project_id: project_id,
            run_id: run_id,
            snapshot_id: checkpoint.id,
            evidence_snapshot_id: snapshot_id,
            decision: to_string(decision),
            reason: to_string(reason),
            chunk: i,
            idx: chunk,
            decided: map_size(decisions),
            inserted_at: inserted_at
          }
        )
      end)
    end)

    primary
  end

  # The baseline's tests the run's stored selection skipped are those it
  # didn't select; the shadow decision covers the primary checkpoint's.
  defp compare(project_id, run_id, decisions) do
    run_selected = project_id |> Storage.list_run_tests(run_id) |> MapSet.new(& &1.test_case_id)

    %{
      only_shadow_skipped:
        (
          for_result = for({id, %{decision: :skipped}} <- decisions, MapSet.member?(run_selected, id), do: id)
          Enum.sort(for_result)
        ),
      only_run_skipped:
        (
          for_result = for({id, %{decision: :selected}} <- decisions, not MapSet.member?(run_selected, id), do: id)
          Enum.sort(for_result)
        )
    }
  end
end
