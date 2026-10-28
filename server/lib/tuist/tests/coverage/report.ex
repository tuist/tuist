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

  defp target(target), do: Map.put(target, :coverage, Coverage.percentage(target.covered_lines, target.executable_lines))

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp iso8601(%NaiveDateTime{} = value),
    do: value |> NaiveDateTime.truncate(:second) |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()

  defp iso8601(%DateTime{} = value), do: value |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  defp iso8601(nil), do: nil
end
