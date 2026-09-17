defmodule Tuist.Tests.Coverage.Comparison do
  @moduledoc """
  A test run's coverage against its baseline: the newest full run of the
  same scheme on the base branch, at the run's merge base or the nearest
  ancestor of it the project's commit graph knows (`Tuist.GitHistory`).

  What can be compared depends on the run:

    * A **full** run compares its total, its targets and its files with the
      baseline's.
    * A **partial** run (selective testing, `-only-testing`) has no total
      delta: the tests it skipped would read as coverage lost. Its files are
      compared only where some test executed the file in the run, the one
      sign that the file's tests ran.
    * **Patch coverage** is the share of the changed executable lines the
      run covered, from the run's per-line counts and the hunks the client
      recorded against the merge base (`Tuist.Tests.TestRunChangedFile`). It
      is exact on a full run. On a partial run it is valid only when every
      changed file's tests ran, which the run cannot prove, so it is off
      unless the project turned it on (`coverage_patch_partial_runs`).
    * **Gaps** are the changed files with executable lines in their hunks
      that no test executed.

  When no baseline can be resolved, the comparison says why rather than
  comparing against some other run.
  """

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.GitHistory
  alias Tuist.Projects.Project
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Test
  alias Tuist.Tests.TestRunChangedFile

  @doc """
  Resolves the baseline of a run: `{:ok, baseline}` with the baseline run's
  id, commit, totals and its distance in commits from the run's merge base,
  or `{:error, reason}` where `reason` is a map with a `:kind` and what it
  concerns.

  Kinds: `:no_merge_base` (a pull request whose merge base is unknown),
  `:no_history` (the commit to walk from is not in the project's commit
  graph), `:no_full_runs` (the base branch has no full run of the scheme in
  the window) and `:no_ancestor_run` (it has, but none on an ancestor within
  the window's commits).
  """
  def baseline(%Project{} = project, %Test{} = run) do
    settings = GitHistory.settings(project)
    base_branch = base_branch(project, run)

    candidates = candidate_runs(project.id, run, base_branch, settings.window_days)

    with {:ok, start_sha} <- start_sha(project, run, base_branch),
         :ok <- ensure_candidates(candidates, run, base_branch, settings),
         {:ok, {sha, depth}} <- nearest_candidate(project.id, run, start_sha, base_branch, candidates, settings) do
      {:ok, Map.merge(Map.fetch!(candidates, sha), %{commit: sha, depth: depth, branch: base_branch})}
    end
  end

  @doc """
  The run's coverage next to its baseline's, with the deltas the run's kind
  allows, its patch coverage and its gaps. `run_summary` is
  `Tuist.Tests.Coverage.run_summary/2` for the run, so a caller that already
  has it does not pay for it twice.
  """
  def compare(%Project{} = project, %Test{} = run, opts \\ []) do
    summary = Keyword.get_lazy(opts, :run_summary, fn -> Coverage.run_summary(run.project_id, run.id) end)

    if is_nil(summary) do
      nil
    else
      {baseline, baseline_reason} =
        case baseline(project, run) do
          {:ok, baseline} -> {baseline, nil}
          {:error, reason} -> {nil, reason}
        end

      partial = summary.partial

      run_files = Coverage.merged_files(run.project_id, run.id)
      baseline_files = if baseline, do: Coverage.merged_files(run.project_id, baseline.test_run_id), else: []

      Map.merge(
        %{
          run: %{
            id: run.id,
            partial: partial,
            covered_lines: summary.covered_lines,
            executable_lines: summary.executable_lines,
            coverage: Coverage.percentage(summary.covered_lines, summary.executable_lines)
          },
          baseline:
            baseline &&
              Map.put(baseline, :coverage, Coverage.percentage(baseline.covered_lines, baseline.executable_lines)),
          baseline_reason: baseline_reason,
          total_delta:
            if baseline && not partial do
              delta(
                Coverage.percentage(summary.covered_lines, summary.executable_lines),
                Coverage.percentage(baseline.covered_lines, baseline.executable_lines)
              )
            end,
          targets: target_deltas(run_files, baseline_files, baseline, partial),
          files: file_deltas(run_files, baseline_files, baseline, partial)
        },
        patch(project, run, partial, run_files)
      )
    end
  end

  @doc """
  Patch coverage and gaps alone, for a run whose baseline is not needed:
  `%{patch: ..., gaps: [...]}`. `patch.status` is `:available` with the
  counts, or `:unavailable` with a `:reason` (`:partial_run`, `:no_history`,
  `:truncated`).
  """
  def patch(%Project{} = project, %Test{} = run, partial, run_files \\ nil) do
    run_files = run_files || Coverage.merged_files(run.project_id, run.id)
    changed = changed_files(run.project_id, run.id)

    cond do
      partial and not project.coverage_patch_partial_runs ->
        %{patch: %{status: :unavailable, reason: :partial_run}, gaps: []}

      changed == [] and not history_collected?(run) ->
        %{patch: %{status: :unavailable, reason: :no_history, detail: run.history_fallback_reason}, gaps: []}

      true ->
        patch_from_changes(run, changed, run_files)
    end
  end

  defp patch_from_changes(run, changed, run_files) do
    files_by_path = Map.new(run_files, &{&1.path, &1})

    {candidates, excluded} =
      changed
      |> Enum.reject(&(&1.status == "deleted"))
      |> Enum.split_with(fn file -> not file.truncated and Map.has_key?(files_by_path, file.path) end)

    lines_by_path = Coverage.line_counts(run.project_id, run.id, Enum.map(candidates, & &1.path))

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
        end)

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

  defp history_collected?(%Test{history_source: source}), do: source not in [nil, "", "none"]

  @doc """
  A sentence for a reason a baseline or a patch is missing (the maps
  `baseline/2` and `patch/4` return), for the PR comment and the check run.
  The dashboard translates its own.
  """
  def reason_text(%{kind: :no_merge_base, base_branch: branch} = reason),
    do: with_detail("the merge base with `#{branch}` is unknown", reason)

  def reason_text(%{kind: :no_history, commit: ""} = reason), do: with_detail("the run's commit is unknown", reason)

  def reason_text(%{kind: :no_history, commit: sha} = reason),
    do: with_detail("commit `#{String.slice(sha, 0, 7)}` is not in the project's Git history", reason)

  def reason_text(%{kind: :no_full_runs, base_branch: branch, scheme: scheme, window_days: days}),
    do: "no full coverage run of `#{scheme}` on `#{branch}` in the last #{days} days"

  def reason_text(%{kind: :no_ancestor_run, base_branch: branch, commit: sha, window_commits: commits}),
    do: "no full run on `#{branch}` within #{commits} commits before `#{String.slice(sha, 0, 7)}`"

  def reason_text(%{reason: :partial_run}), do: "the run skipped tests"
  def reason_text(%{kind: :partial_run}), do: "the run skipped tests"

  def reason_text(%{reason: :no_history} = reason),
    do: with_detail("the changed files are unknown, since the run's Git history was not collected", reason)

  def reason_text(_reason), do: "unknown"

  defp with_detail(text, %{detail: detail}) when is_binary(detail) and detail != "", do: "#{text} (#{detail})"
  defp with_detail(text, _reason), do: text

  @doc "The files the run changed against its merge base, as the client recorded them."
  def changed_files(project_id, test_run_id) do
    ClickHouseRepo.all(
      from(f in TestRunChangedFile,
        where: f.project_id == ^project_id and f.test_run_id == ^test_run_id,
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

  defp target_deltas(run_files, baseline_files, baseline, partial) do
    run_targets = totals_by_target(run_files)
    baseline_targets = totals_by_target(baseline_files)

    run_targets
    |> Map.keys()
    |> MapSet.new()
    |> MapSet.union(MapSet.new(Map.keys(baseline_targets)))
    |> Enum.map(fn name ->
      current = Map.get(run_targets, name)
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
  # does not, are listed: the unchanged ones are the bulk of any run and say
  # nothing about the change. On a partial run a file no test executed
  # cannot be compared, and a file only the baseline has may simply not have
  # been exercised, so neither is listed.
  defp file_deltas(_run_files, _baseline_files, nil, _partial), do: []

  defp file_deltas(run_files, baseline_files, baseline, partial) do
    run_by_path = Map.new(run_files, &{&1.path, &1})
    baseline_by_path = Map.new(baseline_files, &{&1.path, &1})

    run_by_path
    |> Map.keys()
    |> MapSet.new()
    |> MapSet.union(MapSet.new(Map.keys(baseline_by_path)))
    |> Enum.map(fn path ->
      path
      |> entry(Map.get(run_by_path, path), Map.get(baseline_by_path, path), baseline, partial)
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
      delta: if(comparable?(current, baseline_coverage, partial), do: delta(coverage, baseline_coverage))
    }
  end

  defp percentage_of(nil), do: nil

  defp percentage_of(%{covered_lines: covered, executable_lines: executable}),
    do: Coverage.percentage(covered, executable)

  # On a partial run a file no test executed says nothing about the change.
  defp comparable?(nil, _baseline_coverage, _partial), do: false
  defp comparable?(_current, nil, _partial), do: false
  defp comparable?(current, _baseline_coverage, partial), do: not partial or current.covered_lines > 0

  defp delta(current, previous), do: Float.round(current - previous, 1)

  defp base_branch(%Project{default_branch: default_branch}, %Test{base_branch: base}) do
    if base in [nil, ""], do: default_branch, else: base
  end

  # A pull request is compared from its merge base; a run on the base branch
  # itself from the commit before it, so the comparison is with the previous
  # state of the branch and never with itself.
  defp start_sha(project, %Test{is_pull_request: true} = run, base_branch) do
    cond do
      run.merge_base_sha not in [nil, ""] ->
        {:ok, run.merge_base_sha}

      head = GitHistory.branch_head(project.id, base_branch) ->
        case GitHistory.merge_base(project.id, run.git_commit_sha, head) do
          nil -> {:error, %{kind: :no_merge_base, base_branch: base_branch, detail: run.history_fallback_reason}}
          sha -> {:ok, sha}
        end

      true ->
        {:error, %{kind: :no_merge_base, base_branch: base_branch, detail: run.history_fallback_reason}}
    end
  end

  defp start_sha(_project, %Test{git_commit_sha: sha}, _base_branch), do: {:ok, sha}

  defp ensure_candidates(candidates, run, base_branch, settings) do
    if map_size(candidates) == 0 do
      {:error, %{kind: :no_full_runs, base_branch: base_branch, scheme: run.scheme, window_days: settings.window_days}}
    else
      :ok
    end
  end

  defp nearest_candidate(project_id, run, start_sha, base_branch, candidates, settings) do
    cond do
      Map.has_key?(candidates, start_sha) ->
        {:ok, {start_sha, 0}}

      not GitHistory.known?(project_id, start_sha) ->
        {:error, %{kind: :no_history, commit: start_sha, detail: run.history_fallback_reason}}

      true ->
        case GitHistory.nearest_ancestor(project_id, start_sha, Map.keys(candidates), max_depth: settings.window_commits) do
          nil ->
            {:error,
             %{
               kind: :no_ancestor_run,
               commit: start_sha,
               base_branch: base_branch,
               window_commits: settings.window_commits
             }}

          found ->
            {:ok, found}
        end
    end
  end

  # The newest full run per commit of the base branch with the run's scheme
  # and build system, within the history window. A run on the base branch
  # never counts as its own baseline.
  defp candidate_runs(project_id, run, base_branch, window_days) do
    since = NaiveDateTime.add(NaiveDateTime.utc_now(), -window_days, :day)

    runs =
      from(t in Test,
        where: t.project_id == ^project_id and t.git_branch == ^base_branch and t.scheme == ^run.scheme,
        where: t.build_system == ^run.build_system and t.ran_at >= ^since and t.id != ^run.id,
        group_by: t.id,
        select: %{id: t.id, git_commit_sha: fragment("any(?)", t.git_commit_sha), ran_at: min(t.ran_at)}
      )

    runs = if run.is_pull_request, do: runs, else: where(runs, [t], t.git_commit_sha != ^run.git_commit_sha)

    from(c in subquery(Coverage.full_run_totals_query(project_id)),
      join: t in subquery(runs),
      on: t.id == c.test_run_id,
      group_by: t.git_commit_sha,
      select: %{
        git_commit_sha: t.git_commit_sha,
        test_run_id: type(fragment("argMax(?, ?)", c.test_run_id, t.ran_at), Ecto.UUID),
        ran_at: max(t.ran_at),
        covered_lines: fragment("argMax(?, ?)", c.covered_lines, t.ran_at),
        executable_lines: fragment("argMax(?, ?)", c.executable_lines, t.ran_at)
      }
    )
    |> ClickHouseRepo.all()
    |> Map.new(&{&1.git_commit_sha, Map.delete(&1, :git_commit_sha)})
  end
end
