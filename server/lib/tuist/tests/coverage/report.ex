defmodule Tuist.Tests.Coverage.Report do
  @moduledoc """
  Coverage figures in the shape the API and the MCP tools return them: the
  same numbers the dashboard shows, with reasons spelled out as a `kind` and
  a sentence, so an agent can act on them without reading the dashboard.
  """

  alias Tuist.GitHistory
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Comparison
  alias Tuist.Tests.Test

  @doc "A run's coverage: totals, targets, where it sits in Git history and its commit's baseline."
  def run(project, %Test{} = run, summary) do
    Map.merge(
      %{
        test_run_id: run.id,
        scheme: run.scheme,
        git_branch: run.git_branch,
        git_commit_sha: run.git_commit_sha,
        ran_at: iso8601(run.ran_at),
        partial: summary.partial,
        covered_lines: summary.covered_lines,
        executable_lines: summary.executable_lines,
        coverage: Coverage.percentage(summary.covered_lines, summary.executable_lines),
        execution_mode: run.execution_mode,
        targets: Enum.map(Coverage.targets_for_run(run.project_id, run.id), &target/1),
        git_history: git_history(project, run)
      },
      baseline(project, run)
    )
  end

  @doc """
  A commit's coverage (`Tuist.Tests.Coverage.Commits.summary/2` with its
  targets): the union of its runs, its measured set, whether it is
  complete, and its baseline or the reason there is none.
  """
  def commit(project, summary, targets) do
    Map.merge(
      %{
        git_commit_sha: summary.git_commit_sha,
        covered_lines: summary.covered_lines,
        executable_lines: summary.executable_lines,
        coverage: summary.coverage,
        measured_files_count: summary.files_count,
        unmeasured_files_count: summary.unmeasured_files_count,
        schemes: summary.schemes,
        partial_schemes: summary.partial_schemes,
        partial: summary.partial_schemes != [],
        complete: summary.complete,
        completeness: summary.completeness,
        test_run_ids: summary.test_run_ids,
        measured_at: iso8601(summary.inserted_at),
        targets: Enum.map(targets, &target/1)
      },
      baseline(project, Comparison.from_commit(project, summary.git_commit_sha))
    )
  end

  @doc "Where a run sits in the repository's history, as the client or the provider recorded it."
  def git_history(project, %Test{} = run) do
    %{
      git_dirty: run.git_dirty,
      base_branch: run.base_branch,
      merge_base_sha: run.merge_base_sha,
      is_pull_request: run.is_pull_request,
      pull_request_number: run.pull_request_number,
      git_object_format: run.git_object_format,
      history_source: run.history_source,
      history_fallback_reason: run.history_fallback_reason,
      tracked_files_count: tracked_files_count(project, run),
      commit_files_listed: listing_stored?(run)
    }
  end

  @doc "The head's baseline, or the reason there is none, under `baseline` and `baseline_reason`."
  def baseline(project, head) do
    case Comparison.baseline(project, head) do
      {:ok, baseline} -> %{baseline: baseline_map(baseline), baseline_reason: nil}
      {:error, reason} -> %{baseline: nil, baseline_reason: reason(reason)}
    end
  end

  @doc "A comparison (`Tuist.Tests.Coverage.Comparison.compare/3`) as the API returns it."
  def comparison(comparison) do
    %{
      commit: comparison.commit,
      baseline: comparison.baseline && baseline_map(comparison.baseline),
      baseline_reason: comparison.baseline_reason && reason(comparison.baseline_reason),
      total_delta: comparison.total_delta,
      schemes: comparison.schemes,
      targets:
        Enum.map(
          comparison.targets,
          &Map.take(&1, [:name, :covered_lines, :executable_lines, :coverage, :baseline_coverage, :delta])
        ),
      files:
        Enum.map(
          comparison.files,
          &Map.take(&1, [:path, :covered_lines, :executable_lines, :coverage, :baseline_coverage, :delta])
        ),
      patch: patch(comparison.patch),
      gaps: comparison.gaps
    }
  end

  @doc "One of a commit's files with its line counts, least covered first when listed."
  def file(file) do
    %{
      path: file.path,
      git_blob_id: file.git_blob_id,
      targets: file.targets,
      covered_lines: file.covered_lines,
      executable_lines: file.executable_lines,
      coverage: Coverage.percentage(file.covered_lines, file.executable_lines)
    }
  end

  @doc "A file's detail (`Tuist.Tests.Coverage.file_detail/3`): per-line counts, uncovered ranges and functions."
  def file_detail(detail) do
    detail
    |> file()
    |> Map.merge(%{
      lines: Enum.map(detail.lines, &Tuple.to_list/1),
      uncovered_ranges: detail.uncovered_ranges && Enum.map(detail.uncovered_ranges, &Tuple.to_list/1),
      functions: detail.functions
    })
  end

  @doc "A commit of a branch's history (`Tuist.Tests.Coverage.History.branch_history/3`)."
  def history_commit(row) do
    Map.merge(
      %{
        git_commit_sha: row.git_commit_sha,
        depth: row.depth,
        committed_at: iso8601(Map.get(row, :committed_at)),
        measured: row.measured,
        chained: row.chained
      },
      if(row.measured, do: measurement(row), else: %{})
    )
  end

  @doc "A branch's head measurement (`Tuist.Tests.Coverage.History.branches/2`)."
  def branch(row) do
    Map.merge(measurement(row), %{
      git_branch: row.git_branch,
      chained: row.chained,
      ordered_by: Atom.to_string(row.ordered_by),
      delta: row.delta
    })
  end

  @doc "A pull request's commit with coverage (`Tuist.Tests.Coverage.History.pull_request_commits/3`)."
  def pull_request_commit(row) do
    Map.merge(measurement(row), %{
      git_branch: row.git_branch,
      base_branch: row.base_branch,
      ran_at: iso8601(row.ran_at)
    })
  end

  defp measurement(row) do
    %{
      git_commit_sha: row.git_commit_sha,
      covered_lines: row.covered_lines,
      executable_lines: row.executable_lines,
      coverage: row.coverage,
      schemes: row.schemes,
      partial_schemes: row.partial_schemes,
      partial: row.partial_schemes != [],
      complete: row.complete,
      completeness: row.completeness,
      test_run_ids: row.test_run_ids,
      measured_at: iso8601(Map.get(row, :inserted_at))
    }
  end

  defp target(target), do: Map.put(target, :coverage, Coverage.percentage(target.covered_lines, target.executable_lines))

  defp tracked_files_count(project, %Test{git_repository_id: repository_id, git_commit_sha: sha})
       when is_integer(repository_id) and repository_id > 0 and is_binary(sha) and sha != "",
       do: length(GitHistory.tracked_files(project, repository_id, sha))

  defp tracked_files_count(_project, _run), do: 0

  defp listing_stored?(%Test{git_repository_id: repository_id, git_commit_sha: sha})
       when is_integer(repository_id) and repository_id > 0 and is_binary(sha) and sha != "",
       do: GitHistory.listing_stored?(repository_id, sha)

  defp listing_stored?(_run), do: false

  defp baseline_map(baseline) do
    %{
      commit: baseline.commit,
      branch: baseline.branch,
      depth: baseline.depth,
      measured_at: iso8601(baseline.inserted_at),
      covered_lines: baseline.covered_lines,
      executable_lines: baseline.executable_lines,
      coverage: Coverage.percentage(baseline.covered_lines, baseline.executable_lines),
      schemes: baseline.schemes,
      partial_schemes: baseline.partial_schemes,
      complete: baseline.complete,
      test_run_ids: baseline.test_run_ids
    }
  end

  defp patch(%{status: :available} = patch) do
    %{
      status: "available",
      covered_lines: patch.covered_lines,
      executable_lines: patch.executable_lines,
      coverage: patch.coverage,
      files:
        Enum.map(patch.files, fn file ->
          file
          |> Map.take([:path, :status, :covered_lines, :executable_lines, :coverage])
          |> Map.put(:uncovered_ranges, Enum.map(file.uncovered_ranges, &Tuple.to_list/1))
        end),
      skipped: Enum.map(patch.skipped, &%{path: &1.path, reason: Atom.to_string(&1.reason)})
    }
  end

  defp patch(%{status: :unavailable} = patch) do
    %{status: "unavailable", reason: reason(patch)}
  end

  defp reason(%{kind: kind} = reason), do: %{kind: Atom.to_string(kind), message: Comparison.reason_text(reason)}
  defp reason(%{reason: kind} = reason), do: %{kind: Atom.to_string(kind), message: Comparison.reason_text(reason)}

  defp iso8601(%NaiveDateTime{} = value),
    do: value |> NaiveDateTime.truncate(:second) |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()

  defp iso8601(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp iso8601(nil), do: nil
end
