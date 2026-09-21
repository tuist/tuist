defmodule Tuist.Tests.Coverage.Comparison do
  @moduledoc """
  A commit's coverage against its baseline: the nearest measured ancestor of
  the commit's merge base with its base branch, walked first-parent through
  the repository's commit graph (`Tuist.GitHistory`).

  The comparison is always commit against ancestor. A pull request's commit
  starts from its merge base with the base branch, so the branch's own
  earlier pushes are never the baseline (they lie between the merge base and
  the head); a commit on the base branch itself starts from its first
  parent, so it is compared with the previous state of the branch. Nothing
  is stored to make that so: the skip set belongs to the pair of head and
  base, and a fast-forward merge, a stacked branch or a rebase would break a
  stored mark.

  What can be compared depends on how the two commits were measured
  (`Tuist.Tests.Coverage.Commits`):

    * The **total** and its delta only when both commits measured the same
      schemes and the head measured every one of them fully: a missing or
      partial scheme would read as coverage lost. Per scheme, the totals are
      always shown side by side.
    * **Targets and files** are compared over the union of each commit's
      runs; on a head with partial schemes, only files some test executed.
    * **Patch coverage** is the share of the changed executable lines any of
      the head's runs covered, from the per-line counts and the hunks the
      client recorded against the merge base (`Tuist.Tests.TestRunChangedFile`).
      It is exact when the head measured fully; on partial measurements it
      counts the changed lines the tests that ran covered, so it can read
      lower than a full run would.
    * **Gaps** are the changed files with executable lines in their hunks
      that no test executed.

  Both sides leave out the paths the project excludes now
  (`Tuist.Tests.Coverage.ExcludedPaths`): totals are recomputed from the
  retained files, so a change to the exclusions never reads as coverage
  gained or lost. Changed files the exclusions match are listed among the
  patch's skipped files as `excluded`.

  When no baseline can be resolved, the comparison says why rather than
  comparing against some other commit.
  """

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.GitHistory
  alias Tuist.Projects.Project
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.ExcludedPaths
  alias Tuist.Tests.Coverage.Reported
  alias Tuist.Tests.Test
  alias Tuist.Tests.TestRunChangedFile

  @doc """
  Where a commit stands for a comparison: what `baseline/2` and `compare/3`
  need to know about the head, taken from a run (`from_run/2`) or given by a
  caller that has a commit and a base branch.
  """
  def from_run(%Project{} = project, %Test{} = run) do
    %{
      project_id: project.id,
      sha: run.git_commit_sha || "",
      repository_id: run.git_repository_id || 0,
      base_branch: base_branch(project, run.base_branch),
      is_pull_request: run.is_pull_request == true,
      pull_request_number: run.pull_request_number || 0,
      git_ref: run.git_ref || "",
      merge_base_sha: run.merge_base_sha || "",
      history_fallback_reason: run.history_fallback_reason || "",
      run_ids: []
    }
  end

  @doc """
  The same for a commit: its runs say what base branch it was measured
  against, whether it was a pull request and its merge base (the newest run
  that knows wins).
  """
  def from_commit(%Project{} = project, sha) do
    runs = commit_runs(project.id, sha)
    with_history = Enum.filter(runs, &(&1.merge_base_sha != "" or &1.base_branch != ""))
    known = List.last(with_history) || List.last(runs) || %{}

    %{
      project_id: project.id,
      sha: sha,
      repository_id: runs |> Enum.map(& &1.git_repository_id) |> Enum.max(fn -> 0 end),
      base_branch: base_branch(project, Map.get(known, :base_branch)),
      is_pull_request: Enum.any?(runs, & &1.is_pull_request),
      pull_request_number: runs |> Enum.map(& &1.pull_request_number) |> Enum.max(fn -> 0 end),
      git_ref: Map.get(known, :git_ref) || "",
      merge_base_sha: Map.get(known, :merge_base_sha) || "",
      history_fallback_reason: Map.get(known, :history_fallback_reason) || "",
      run_ids: Enum.map(runs, & &1.id)
    }
  end

  @doc """
  Resolves the baseline of a head (`from_run/2` or `from_commit/2`):
  `{:ok, baseline}` with the baseline commit, its totals, its measured set
  and its distance in commits from the start of the walk, or
  `{:error, reason}` where `reason` is a map with a `:kind` and what it
  concerns.

  Kinds: `:no_history` (the head has no commit, or the commit to walk from
  is not in the repository's graph), `:no_merge_base` (a pull request whose
  merge base is unknown), `:no_measured_commits` (no measured commit within
  the window at all), `:no_ancestor_commit` (some, but none on the ancestry
  within the window's commits), `:measured_set_mismatch` (the nearest
  measured ancestor measured a different set of schemes, so a total would
  compare unlike with unlike) and `:dirty_checkout` (the run measured a
  checkout with uncommitted changes, so it stands for no commit).
  """
  def baseline(%Project{} = project, %Test{} = run), do: baseline(project, from_run(project, run))

  def baseline(%Project{} = project, %{sha: _} = head) do
    settings = GitHistory.settings(project)
    candidates = candidate_commits(project.id, head.sha, settings.window_days)

    with {:ok, start_sha} <- start_sha(head),
         :ok <- ensure_candidates(candidates, head, settings),
         {:ok, {sha, depth}} <- nearest_candidate(head, start_sha, candidates, settings),
         {:ok, baseline} <- comparable(Map.fetch!(candidates, sha), head) do
      {:ok, Map.merge(baseline, %{commit: sha, depth: depth, branch: head.base_branch})}
    end
  end

  # A pull request is compared from its merge base; a commit on the base
  # branch itself from its first parent, so the comparison is with the
  # previous state of the branch and never with itself.
  defp start_sha(%{sha: ""} = head), do: {:error, %{kind: :no_history, commit: "", detail: head.history_fallback_reason}}

  defp start_sha(%{repository_id: 0} = head),
    do: {:error, %{kind: :no_history, commit: head.sha, detail: head.history_fallback_reason}}

  defp start_sha(%{is_pull_request: true} = head) do
    cond do
      head.merge_base_sha != "" ->
        {:ok, head.merge_base_sha}

      branch_head = GitHistory.branch_head(head.repository_id, head.base_branch) ->
        case GitHistory.merge_base(head.repository_id, head.sha, branch_head) do
          nil -> {:error, %{kind: :no_merge_base, base_branch: head.base_branch, detail: head.history_fallback_reason}}
          sha -> {:ok, sha}
        end

      true ->
        {:error, %{kind: :no_merge_base, base_branch: head.base_branch, detail: head.history_fallback_reason}}
    end
  end

  defp start_sha(head) do
    case GitHistory.first_parent(head.repository_id, head.sha) do
      nil -> {:error, %{kind: :no_history, commit: head.sha, detail: head.history_fallback_reason}}
      parent -> {:ok, parent}
    end
  end

  defp ensure_candidates(candidates, head, settings) do
    if map_size(candidates) == 0 do
      {:error, %{kind: :no_measured_commits, base_branch: head.base_branch, window_days: settings.window_days}}
    else
      :ok
    end
  end

  defp nearest_candidate(head, start_sha, candidates, settings) do
    cond do
      Map.has_key?(candidates, start_sha) ->
        {:ok, {start_sha, 0}}

      not GitHistory.known?(head.repository_id, start_sha) ->
        {:error, %{kind: :no_history, commit: start_sha, detail: head.history_fallback_reason}}

      true ->
        head.repository_id
        |> GitHistory.first_parent_chain(start_sha, max_depth: settings.window_commits)
        |> Enum.find(fn {sha, _depth, _at} -> Map.has_key?(candidates, sha) end)
        |> case do
          nil ->
            {:error,
             %{
               kind: :no_ancestor_commit,
               commit: start_sha,
               base_branch: head.base_branch,
               window_commits: settings.window_commits
             }}

          {sha, depth, _at} ->
            {:ok, {sha, depth}}
        end
    end
  end

  # The head's measured set is only known once its runs are published; a
  # head with no published commit yet (a run compared before the fold) is
  # compared with whatever the ancestor measured.
  defp comparable(candidate, head) do
    case Commits.summary_for(head) do
      %{schemes: schemes} when schemes != candidate.schemes ->
        {:error,
         %{
           kind: :measured_set_mismatch,
           commit: candidate.git_commit_sha,
           schemes: schemes,
           baseline_schemes: candidate.schemes
         }}

      _ ->
        {:ok, candidate}
    end
  end

  # The measured commits within the window, keyed by SHA.
  # A commit is never its own baseline.
  defp candidate_commits(project_id, head_sha, window_days) do
    since = NaiveDateTime.add(NaiveDateTime.utc_now(), -window_days, :day)

    from(c in subquery(Commits.commits_query(project_id)),
      where: c.inserted_at >= ^since and c.git_commit_sha != ^head_sha
    )
    |> ClickHouseRepo.all()
    |> Map.new(&{&1.git_commit_sha, &1})
  end

  @doc """
  The commit's coverage next to its baseline's, with the deltas the
  measurements allow, per-scheme totals, its patch coverage and its gaps.
  Nil when nothing measured the commit. Accepts a run (compared as its
  commit; a run without a commit is described alone, with the reason) or a
  head from `from_commit/2`.
  """
  def compare(project, head, opts \\ [])

  # A run with no commit, and a run from a dirty checkout, are compared as
  # themselves: the dirty one measured code that is not its commit's, so it
  # joins no commit and the commit's comparison would be about other runs.
  def compare(%Project{} = project, %Test{git_commit_sha: sha, git_dirty: dirty} = run, opts)
      when sha in [nil, ""] or dirty do
    excluded = ExcludedPaths.pattern_for_project(project)

    reason =
      if dirty,
        do: %{kind: :dirty_checkout, commit: sha || ""},
        else: %{kind: :no_history, commit: "", detail: run.history_fallback_reason}

    case Keyword.get_lazy(opts, :run_summary, fn -> Coverage.run_summary(run.project_id, run.id, excluded: excluded) end) do
      nil ->
        nil

      summary ->
        %{
          commit:
            commit_figure("", summary.partial, summary.covered_lines, summary.executable_lines, [run.scheme || ""], []),
          baseline: nil,
          baseline_reason: reason,
          total_delta: nil,
          schemes: [],
          targets: [],
          files: [],
          patch: %{status: :unavailable, reason: reason.kind, detail: Map.get(reason, :detail)},
          gaps: []
        }
    end
  end

  def compare(%Project{} = project, %Test{} = run, opts),
    do: compare(project, from_commit(project, run.git_commit_sha), opts)

  def compare(%Project{} = project, %{sha: sha} = head, _opts) do
    case Commits.summary(project.id, sha) || Commits.recompute(project, sha) do
      nil -> nil
      summary -> compare_summary(project, head, summary)
    end
  end

  defp compare_summary(project, %{sha: sha} = head, summary) do
    excluded = ExcludedPaths.pattern_for_project(project)

    {baseline, baseline_reason} =
      case baseline(project, head) do
        {:ok, baseline} -> {baseline, nil}
        {:error, reason} -> {nil, reason}
      end

    partial = summary.partial_schemes != []

    # A commit whose skipped tests were all carried forward is compared target
    # by target and file by file with what a full run would have measured, not
    # with what its runs happened to execute: a file only a skipped test covers
    # did not fall. Its own totals and its patch stay what was measured.
    measured_files = Commits.merged_files(project.id, sha, excluded: excluded)
    carried? = partial and Map.get(summary, :reported_kind) == "reported"

    head_files =
      if carried?, do: Reported.merged_files(project, sha, measured_files, excluded: excluded), else: measured_files

    baseline_files = if baseline, do: Commits.merged_files(project.id, baseline.commit, excluded: excluded), else: []
    baseline = baseline && with_retained_totals(baseline, baseline_files)
    head_totals = with_retained_totals(summary, measured_files)

    commit =
      sha
      |> commit_figure(
        partial,
        head_totals.covered_lines,
        head_totals.executable_lines,
        summary.schemes,
        summary.partial_schemes
      )
      |> Map.merge(%{
        complete: summary.complete,
        completeness: summary.completeness,
        reported: Commits.reported_figure(summary)
      })

    Map.merge(
      %{
        commit: commit,
        baseline:
          baseline && Map.put(baseline, :coverage, Coverage.percentage(baseline.covered_lines, baseline.executable_lines)),
        baseline_reason: baseline_reason,
        total_delta: total_delta(commit, baseline, partial),
        schemes: scheme_rows(project.id, sha, (baseline && baseline.commit) || scheme_baseline(baseline_reason)),
        targets: target_deltas(head_files, baseline_files, baseline, partial and not carried?),
        files: file_deltas(head_files, baseline_files, baseline, partial and not carried?)
      },
      patch(project, head, measured_files)
    )
  end

  # The whole is compared when the head measured every scheme fully, or when
  # what its runs skipped was carried forward in full: reported coverage is
  # then what a full run would have measured.
  defp total_delta(_commit, nil, _partial), do: nil

  defp total_delta(%{reported: %{kind: "reported", coverage: coverage}}, baseline, true),
    do: delta(coverage, reported_percentage(baseline))

  defp total_delta(_commit, _baseline, true), do: nil

  defp total_delta(commit, baseline, false),
    do: delta(commit.coverage, Coverage.percentage(baseline.covered_lines, baseline.executable_lines))

  defp reported_percentage(%{
         reported_kind: "reported",
         reported_covered_lines: covered,
         reported_executable_lines: executable
       }), do: Coverage.percentage(covered, executable)

  defp reported_percentage(baseline), do: Coverage.percentage(baseline.covered_lines, baseline.executable_lines)

  defp commit_figure(sha, partial, covered, executable, schemes, partial_schemes) do
    %{
      sha: sha,
      partial: partial,
      covered_lines: covered,
      executable_lines: executable,
      coverage: Coverage.percentage(covered, executable),
      schemes: schemes,
      partial_schemes: partial_schemes
    }
  end

  # The published totals predate any later change to the exclusions; the
  # files, while retained, give the totals under the current ones.
  defp with_retained_totals(figure, []), do: figure

  defp with_retained_totals(figure, files) do
    Map.merge(figure, %{
      covered_lines: files |> Enum.map(& &1.covered_lines) |> Enum.sum(),
      executable_lines: files |> Enum.map(& &1.executable_lines) |> Enum.sum()
    })
  end

  # Each scheme's own total at the head and at the baseline: the rows shown
  # under "any scheme", where a pooled total would compare unlike sets.
  # A measured set that does not match leaves the totals incomparable, but the
  # schemes both commits did measure still compare: that is the whole point of
  # saying which scheme is missing rather than drawing a drop. Every other
  # reason has no ancestor to compare against.
  defp scheme_baseline(%{kind: :measured_set_mismatch, commit: sha}), do: sha
  defp scheme_baseline(_reason), do: nil

  defp scheme_rows(project_id, sha, baseline_sha) do
    head = totals_by_scheme(project_id, sha)
    baseline = if baseline_sha, do: totals_by_scheme(project_id, baseline_sha), else: %{}

    head
    |> Map.keys()
    |> MapSet.new()
    |> MapSet.union(MapSet.new(Map.keys(baseline)))
    |> Enum.sort()
    |> Enum.map(fn scheme ->
      current = Map.get(head, scheme)
      previous = Map.get(baseline, scheme)
      coverage = current && Coverage.percentage(current.covered_lines, current.executable_lines)
      baseline_coverage = previous && Coverage.percentage(previous.covered_lines, previous.executable_lines)

      %{
        scheme: scheme,
        partial: current && current.partial,
        covered_lines: current && current.covered_lines,
        executable_lines: current && current.executable_lines,
        coverage: coverage,
        baseline_coverage: baseline_coverage,
        delta: scheme_delta(current, previous, coverage, baseline_coverage)
      }
    end)
  end

  # Two partial measurements, or a missing side, compare nothing.
  defp scheme_delta(%{partial: false}, %{partial: false}, coverage, baseline_coverage),
    do: delta(coverage, baseline_coverage)

  defp scheme_delta(_current, _previous, _coverage, _baseline_coverage), do: nil

  # Per scheme, the newest full run's totals, or the newest partial one's.
  defp totals_by_scheme(project_id, sha) do
    project_id
    |> Commits.runs(sha)
    |> Enum.group_by(& &1.scheme)
    |> Map.new(fn {scheme, runs} ->
      run = Enum.max_by(runs, &{not &1.partial, &1.ran_at}, fn _a, _b -> true end)
      {scheme, %{covered_lines: run.covered_lines, executable_lines: run.executable_lines, partial: run.partial}}
    end)
  end

  @doc """
  Patch coverage and gaps alone, for a head whose baseline is not needed:
  `%{patch: ..., gaps: [...]}`. `patch.status` is `:available` with the
  counts, or `:unavailable` with a `:reason` (`:no_history`, `:truncated`).
  """
  def patch(%Project{} = project, %{sha: sha} = head, head_files \\ nil) do
    excluded = ExcludedPaths.pattern_for_project(project)
    head_files = head_files || Commits.merged_files(project.id, sha, excluded: excluded)
    changed = changed_files_for_commit(project.id, sha)

    if changed == [] and head.merge_base_sha == "" do
      %{patch: %{status: :unavailable, reason: :no_history, detail: head.history_fallback_reason}, gaps: []}
    else
      patch_from_changes(project.id, sha, changed, head_files, excluded)
    end
  end

  defp patch_from_changes(project_id, sha, changed, head_files, excluded_pattern) do
    files_by_path = Map.new(head_files, &{&1.path, &1})
    excluded_regex = ExcludedPaths.compile(excluded_pattern)

    {excluded_by_project, changed} =
      changed
      |> Enum.reject(&(&1.status == "deleted"))
      |> Enum.split_with(&ExcludedPaths.excluded?(excluded_regex, &1.path))

    {candidates, excluded} =
      Enum.split_with(changed, fn file -> not file.truncated and Map.has_key?(files_by_path, file.path) end)

    lines_by_path = Commits.line_counts(project_id, sha, Enum.map(candidates, & &1.path), excluded: excluded_pattern)

    {files, skipped} =
      Enum.reduce(candidates, {[], []}, fn file, {files, skipped} ->
        coverage_row = Map.fetch!(files_by_path, file.path)

        cond do
          not same_blob?(coverage_row.git_blob_id, file.git_blob_id) ->
            {files, [%{path: file.path, reason: :stale} | skipped]}

          Map.get(lines_by_path, file.path, []) == [] ->
            {files, [%{path: file.path, reason: :no_line_data} | skipped]}

          true ->
            {[patch_file(file, Map.fetch!(lines_by_path, file.path)) | files], skipped}
        end
      end)

    skipped =
      skipped ++
        Enum.map(excluded, fn file ->
          %{path: file.path, reason: if(file.truncated, do: :truncated, else: :not_instrumented)}
        end) ++
        Enum.map(excluded_by_project, &%{path: &1.path, reason: :excluded})

    files = files |> Enum.filter(&(&1.executable_lines > 0)) |> Enum.sort_by(&{&1.coverage, &1.path})
    covered = files |> Enum.map(& &1.covered_lines) |> Enum.sum()
    executable = files |> Enum.map(& &1.executable_lines) |> Enum.sum()

    %{
      patch: %{
        status: :available,
        covered_lines: covered,
        executable_lines: executable,
        coverage: Coverage.percentage(covered, executable),
        files: files,
        skipped: Enum.sort_by(skipped, & &1.path)
      },
      gaps: for(file <- files, file.covered_lines == 0, do: Map.take(file, [:path, :executable_lines]))
    }
  end

  # An unknown blob on either side cannot contradict the other; an abbreviated
  # id (what `git diff --raw` prints without `--no-abbrev`) names the same
  # object as the full id it prefixes.
  defp same_blob?(a, b) when a == "" or b == "", do: true
  defp same_blob?(a, b), do: String.starts_with?(a, b) or String.starts_with?(b, a)

  # The executable lines inside the file's hunks, with how many of them ran.
  defp patch_file(file, lines) do
    hunks = Enum.zip(file.hunk_starts, file.hunk_ends)

    in_hunks =
      Enum.filter(lines, fn {line, _count} -> Enum.any?(hunks, fn {first, last} -> line >= first and line <= last end) end)

    covered = Enum.count(in_hunks, fn {_line, count} -> count > 0 end)

    %{
      path: file.path,
      status: file.status,
      covered_lines: covered,
      executable_lines: length(in_hunks),
      coverage: Coverage.percentage(covered, length(in_hunks)),
      uncovered_ranges: Coverage.uncovered_ranges(in_hunks)
    }
  end

  @doc """
  A sentence for a reason a baseline or a patch is missing (the maps
  `baseline/2` and `patch/4` return), for the PR comment and the check run.
  The dashboard translates its own.
  """
  def reason_text(%{kind: :no_merge_base, base_branch: branch} = reason),
    do: with_detail("the merge base with `#{branch}` is unknown", reason)

  def reason_text(%{kind: :no_history, commit: ""} = reason), do: with_detail("the commit is unknown", reason)

  def reason_text(%{kind: :no_history, commit: sha} = reason),
    do: with_detail("commit `#{String.slice(sha, 0, 7)}` is not in the repository's Git history", reason)

  def reason_text(%{kind: :no_measured_commits, base_branch: branch, window_days: days}),
    do: "no measured commit on `#{branch}` in the last #{days} days"

  def reason_text(%{kind: :no_ancestor_commit, base_branch: branch, commit: sha, window_commits: commits}),
    do: "no measured commit on `#{branch}` within #{commits} commits before `#{String.slice(sha, 0, 7)}`"

  def reason_text(%{kind: :measured_set_mismatch, commit: sha, schemes: schemes, baseline_schemes: baseline}),
    do:
      "commit `#{String.slice(sha, 0, 7)}` measured #{schemes_text(baseline)} where this commit measured #{schemes_text(schemes)}"

  def reason_text(%{kind: :partial_run}), do: "some tests were skipped"

  def reason_text(%{kind: :dirty_checkout}),
    do: "the checkout had uncommitted changes, so this run measured code that is not the commit's"

  def reason_text(%{reason: :dirty_checkout}),
    do: "the changed files are unknown, since the checkout had uncommitted changes"

  def reason_text(%{reason: :no_history} = reason),
    do: with_detail("the changed files are unknown, since the run's Git history was not collected", reason)

  def reason_text(_reason), do: "unknown"

  defp schemes_text([]), do: "nothing"
  defp schemes_text(schemes), do: Enum.map_join(schemes, ", ", &"`#{&1}`")

  defp with_detail(text, %{detail: detail}) when is_binary(detail) and detail != "", do: "#{text} (#{detail})"
  defp with_detail(text, _reason), do: text

  @doc "The files the run changed against its merge base, as the client recorded them."
  def changed_files(project_id, test_run_id), do: changed_files_for_runs(project_id, [test_run_id])

  @doc """
  The files the commit changed against its merge base: what the newest of
  the commit's runs that recorded any says.
  """
  def changed_files_for_commit(project_id, sha) do
    project_id
    |> commit_runs(sha)
    |> Enum.reverse()
    |> Enum.find_value([], fn run ->
      case changed_files_for_runs(project_id, [run.id]) do
        [] -> nil
        files -> files
      end
    end)
  end

  defp changed_files_for_runs(project_id, test_run_ids) do
    ClickHouseRepo.all(
      from(f in TestRunChangedFile,
        where: f.project_id == ^project_id and f.test_run_id in ^test_run_ids,
        group_by: f.path,
        select: %{
          path: f.path,
          previous_path: fragment("argMax(?, ?)", f.previous_path, f.inserted_at),
          status: fragment("argMax(?, ?)", f.status, f.inserted_at),
          git_blob_id: fragment("argMax(?, ?)", f.git_blob_id, f.inserted_at),
          hunk_starts: fragment("argMax(?, ?)", f.hunk_starts, f.inserted_at),
          hunk_ends: fragment("argMax(?, ?)", f.hunk_ends, f.inserted_at),
          truncated: fragment("argMax(?, ?)", f.truncated, f.inserted_at)
        },
        order_by: f.path
      )
    )
  end

  # The commit's runs with their history columns, oldest first, one row per
  # run whatever the history rewrites added.
  defp commit_runs(project_id, sha) do
    ClickHouseRepo.all(
      from(t in Test,
        where: t.project_id == ^project_id and t.git_commit_sha == ^sha,
        group_by: t.id,
        having: fragment("argMax(?, ?)", t.git_dirty, t.inserted_at) == false,
        select: %{
          id: t.id,
          git_repository_id: fragment("argMax(?, ?)", t.git_repository_id, t.inserted_at),
          base_branch: fragment("argMax(?, ?)", t.base_branch, t.inserted_at),
          merge_base_sha: fragment("argMax(?, ?)", t.merge_base_sha, t.inserted_at),
          is_pull_request: fragment("argMax(?, ?)", t.is_pull_request, t.inserted_at),
          pull_request_number: fragment("argMax(?, ?)", t.pull_request_number, t.inserted_at),
          git_ref: fragment("any(?)", t.git_ref),
          history_fallback_reason: fragment("argMax(?, ?)", t.history_fallback_reason, t.inserted_at),
          ran_at: min(t.ran_at)
        },
        order_by: [asc: min(t.ran_at)]
      )
    )
  end

  defp target_deltas(head_files, baseline_files, baseline, partial) do
    head_targets = totals_by_target(head_files)
    baseline_targets = totals_by_target(baseline_files)

    head_targets
    |> Map.keys()
    |> MapSet.new()
    |> MapSet.union(MapSet.new(Map.keys(baseline_targets)))
    |> Enum.map(fn name ->
      current = Map.get(head_targets, name)
      previous = Map.get(baseline_targets, name)
      entry(name, current, previous, baseline, partial)
    end)
    |> Enum.sort_by(&{&1.delta || 0.0, &1.name})
  end

  defp totals_by_target(files) do
    files
    |> Enum.flat_map(fn file -> Enum.map(file.targets, &{&1, file}) end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {name, files} ->
      {name,
       %{
         covered_lines: files |> Enum.map(& &1.covered_lines) |> Enum.sum(),
         executable_lines: files |> Enum.map(& &1.executable_lines) |> Enum.sum()
       }}
    end)
  end

  # Only the files whose coverage moved, or that one side has and the other
  # does not, are listed: the unchanged ones are the bulk of any commit and
  # say nothing about the change. On a partial measurement a file no test
  # executed cannot be compared, and a file only the baseline has may simply
  # not have been exercised, so neither is listed.
  defp file_deltas(_head_files, _baseline_files, nil, _partial), do: []

  defp file_deltas(head_files, baseline_files, baseline, partial) do
    head_by_path = Map.new(head_files, &{&1.path, &1})
    baseline_by_path = Map.new(baseline_files, &{&1.path, &1})

    head_by_path
    |> Map.keys()
    |> MapSet.new()
    |> MapSet.union(MapSet.new(Map.keys(baseline_by_path)))
    |> Enum.map(fn path ->
      path
      |> entry(Map.get(head_by_path, path), Map.get(baseline_by_path, path), baseline, partial)
      |> Map.put(:path, path)
    end)
    |> Enum.filter(fn entry ->
      cond do
        is_nil(entry.coverage) -> not partial
        is_nil(entry.baseline_coverage) -> true
        true -> not is_nil(entry.delta) and entry.delta != 0.0
      end
    end)
    |> Enum.sort_by(&{&1.delta || 0.0, &1.name})
  end

  defp entry(name, current, previous, baseline, partial) do
    coverage = percentage_of(current)
    baseline_coverage = if baseline, do: percentage_of(previous)

    %{
      name: name,
      covered_lines: current && current.covered_lines,
      executable_lines: current && current.executable_lines,
      coverage: coverage,
      baseline_coverage: baseline_coverage,
      delta: if(comparable_entry?(current, baseline_coverage, partial), do: delta(coverage, baseline_coverage))
    }
  end

  defp percentage_of(nil), do: nil

  defp percentage_of(%{covered_lines: covered, executable_lines: executable}),
    do: Coverage.percentage(covered, executable)

  # On a partial measurement a file no test executed says nothing about the change.
  defp comparable_entry?(nil, _baseline_coverage, _partial), do: false
  defp comparable_entry?(_current, nil, _partial), do: false
  defp comparable_entry?(current, _baseline_coverage, partial), do: not partial or current.covered_lines > 0

  defp delta(current, previous), do: Float.round(current - previous, 1)

  defp base_branch(%Project{default_branch: default_branch}, base) do
    if base in [nil, ""], do: default_branch, else: base
  end
end
