defmodule Tuist.Tests.Coverage.Report do
  @moduledoc """
  Coverage figures in the shape the API and the MCP tools return them: the
  same numbers the dashboard shows.
  """

  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Commits

  @doc """
  A commit's coverage (`Tuist.Tests.Coverage.Commits.summary/2` with its
  targets): the union of its runs, its measured set and whether it is
  complete.
  """
  def commit(summary, targets) do
    %{
      git_commit_sha: summary.git_commit_sha,
      covered_lines: summary.covered_lines,
      executable_lines: summary.executable_lines,
      coverage: summary.coverage,
      measured_files_count: summary.measured_files_count,
      unmeasured_files_count: summary.unmeasured_files_count,
      schemes: summary.schemes,
      partial_schemes: summary.partial_schemes,
      partial: summary.partial_schemes != [],
      complete: summary.complete,
      completeness: summary.completeness,
      reported: Commits.reported_figure(summary),
      test_run_ids: summary.test_run_ids,
      measured_at: iso8601(summary.inserted_at),
      targets: Enum.map(targets, &target/1)
    }
  end

  @doc "A row of a commit's files (`Tuist.Tests.Coverage.Commits.list_files/5`)."
  def file_row(row) do
    %{
      path: row.path,
      covered_lines: row.covered_lines,
      executable_lines: row.executable_lines,
      coverage: Coverage.percentage(row.covered_lines, row.executable_lines)
    }
  end

  @doc """
  A file's coverage at a commit (`Tuist.Tests.Coverage.Commits.file_detail/4`):
  its figures and functions, and its per-line execution counts with
  `include_lines: true`.
  """
  def file(sha, detail, opts \\ []) do
    file = %{
      git_commit_sha: sha,
      path: detail.path,
      git_blob_id: blank_to_nil(detail.git_blob_id),
      targets: detail.targets,
      covered_lines: detail.covered_lines,
      executable_lines: detail.executable_lines,
      coverage: Coverage.percentage(detail.covered_lines, detail.executable_lines),
      carried_lines: Map.get(detail, :carried_lines, []),
      functions: Enum.map(detail.functions, &function/1)
    }

    if Keyword.get(opts, :include_lines, false),
      do: Map.put(file, :lines, Enum.map(detail.lines, fn {line, count} -> %{line: line, count: count} end)),
      else: file
  end

  defp function(function) do
    %{
      name: function.name,
      line_number: function.line_number,
      execution_count: function.execution_count,
      covered_lines: function.covered_lines,
      executable_lines: function.executable_lines
    }
  end

  @doc """
  A commit of a branch's history (`Tuist.Tests.Coverage.History.commit_cursor_page/3`):
  its status and, once measured, its figure and its change from the complete
  commit before it, which only a complete commit has.
  """
  def commit_row(%{measured: false} = commit) do
    %{
      git_commit_sha: commit.git_commit_sha,
      committed_at: iso8601(commit.committed_at),
      status: "not_measured",
      coverage: nil,
      covered_lines: nil,
      executable_lines: nil,
      change: nil,
      schemes: []
    }
  end

  def commit_row(commit) do
    %{
      git_commit_sha: commit.git_commit_sha,
      committed_at: iso8601(commit.committed_at),
      status: commit |> Commits.status() |> Atom.to_string(),
      coverage: commit.coverage,
      covered_lines: commit.covered_lines,
      executable_lines: commit.executable_lines,
      change: Map.get(commit, :change),
      schemes: commit.schemes
    }
  end

  @doc """
  A run behind a commit or branch (`Tuist.Tests.Coverage.Commits.run_cursor_page/3`):
  `full`, `partial` when it skipped tests on purpose (one that skipped every
  test measured nothing: no lines, 0%), or `discarded` when it ran from a dirty checkout, whose coverage
  never joins its commit's.
  """
  def run_row(run) do
    %{
      test_run_id: run.test_run_id,
      git_commit_sha: run.git_commit_sha,
      scheme: run.scheme,
      status: run_status(run),
      covered_lines: run.covered_lines,
      executable_lines: run.executable_lines,
      coverage: Coverage.percentage(run.covered_lines, run.executable_lines),
      ran_at: iso8601(run.ran_at)
    }
  end

  defp run_status(%{git_dirty: true}), do: "discarded"
  defp run_status(%{partial: true}), do: "partial"
  defp run_status(_run), do: "full"

  @doc "A measured target of a commit (`Tuist.Tests.Coverage.Commits.targets/3`)."
  def target_row(target), do: target |> target() |> Map.put(:measured, true)

  @doc """
  A target the commit's runs took from the binary cache without coverage
  counters (`Tuist.Tests.Coverage.Commits.unmeasured_targets/2`): it has no figure.
  """
  def unmeasured_target_row(name),
    do: %{name: name, files_count: 0, covered_lines: 0, executable_lines: 0, coverage: nil, measured: false}

  @doc """
  A test run's own coverage (`Tuist.Tests.Coverage.Query.test_run/1`), from
  its totals in `coverage_runs`, or nil when it measured nothing.
  """
  def run_coverage(run, totals) do
    %{
      enabled: Map.get(run, :coverage_enabled),
      git_dirty: Map.get(run, :git_dirty) || false,
      measured: not is_nil(totals),
      partial: (totals && totals.partial) || false,
      covered_lines: totals && totals.covered_lines,
      executable_lines: totals && totals.executable_lines,
      coverage: totals && Coverage.percentage(totals.covered_lines, totals.executable_lines)
    }
  end

  defp target(target), do: Map.put(target, :coverage, Coverage.percentage(target.covered_lines, target.executable_lines))

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp iso8601(%NaiveDateTime{} = value),
    do: value |> NaiveDateTime.truncate(:second) |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()

  defp iso8601(%DateTime{} = value), do: value |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  defp iso8601(nil), do: nil
end
