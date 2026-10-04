defmodule Tuist.Tests.Coverage.Report do
  @moduledoc """
  Coverage figures in the shape the API returns them: the same numbers the
  dashboard shows.
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

  defp target(target), do: Map.put(target, :coverage, Coverage.percentage(target.covered_lines, target.executable_lines))

  defp iso8601(%NaiveDateTime{} = value),
    do: value |> NaiveDateTime.truncate(:second) |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()

  defp iso8601(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp iso8601(nil), do: nil
end
