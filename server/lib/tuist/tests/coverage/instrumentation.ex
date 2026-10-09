defmodule Tuist.Tests.Coverage.Instrumentation do
  @moduledoc """
  Whether a commit's runs executed code they couldn't measure. A build
  system that reuses prebuilt code, such as a binary cache, runs it without
  coverage counters, so what the tests executed in it is unknown. Each build
  system says which of its runs did that (`Tuist.Tests.Coverage.Xcode` for
  Xcode); one that reuses nothing says none.
  """
  alias Tuist.Tests.Coverage.Xcode

  @doc """
  The schemes whose coverage is incomplete: a run of the scheme reused
  uninstrumented code, and no run of it executed every test from sources.
  `runs` are the commit's runs as `Tuist.Tests.Coverage.Commits.runs/2` reads
  them.
  """
  def incomplete_schemes(_project_id, []), do: []

  def incomplete_schemes(project_id, runs) do
    uninstrumented =
      runs
      |> Enum.group_by(& &1.build_system, & &1.test_run_id)
      |> Enum.flat_map(fn {build_system, run_ids} -> uninstrumented_runs(build_system, project_id, run_ids) end)
      |> MapSet.new()

    runs
    |> Enum.group_by(& &1.scheme)
    |> Enum.filter(fn {_scheme, scheme_runs} ->
      Enum.any?(scheme_runs, &MapSet.member?(uninstrumented, &1.test_run_id)) and
        not Enum.any?(scheme_runs, &(not &1.partial and not MapSet.member?(uninstrumented, &1.test_run_id)))
    end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.sort()
  end

  defp uninstrumented_runs("xcode", project_id, run_ids), do: Xcode.uninstrumented_runs(project_id, run_ids)
  defp uninstrumented_runs(_build_system, _project_id, _run_ids), do: []
end
