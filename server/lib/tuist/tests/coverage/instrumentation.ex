defmodule Tuist.Tests.Coverage.Instrumentation do
  @moduledoc """
  Whether a commit's runs executed code they couldn't measure, target by
  target. A build system that reuses prebuilt code, such as a binary cache,
  runs it without coverage counters unless the binary was built with them, so
  what the tests executed in a plain binary is unknown. Each build system says
  which targets each of its runs took that way (`Tuist.Tests.Coverage.Xcode`
  for Xcode); one that reuses nothing says none.
  """

  alias Tuist.Tests.Coverage.Xcode

  @doc """
  The targets whose code no run of their scheme measured, as
  `%{scheme => [target]}`: a run of the scheme took the target from the cache
  without counters, and no run that executed every test had it built from
  source or taken instrumented. `runs` are the commit's runs as
  `Tuist.Tests.Coverage.Commits.runs/2` reads them.
  """
  def incomplete_targets(_project_id, []), do: %{}

  def incomplete_targets(project_id, runs) do
    uninstrumented = uninstrumented_targets(project_id, runs)

    runs
    |> Enum.group_by(& &1.scheme)
    |> Enum.flat_map(fn {scheme, scheme_runs} ->
      plain = scheme_runs |> Enum.flat_map(&Map.get(uninstrumented, &1.test_run_id, [])) |> Enum.uniq()

      measured? = fn target ->
        Enum.any?(scheme_runs, &(not &1.partial and target not in Map.get(uninstrumented, &1.test_run_id, [])))
      end

      case plain |> Enum.reject(measured?) |> Enum.sort() do
        [] -> []
        targets -> [{scheme, targets}]
      end
    end)
    |> Map.new()
  end

  @doc "The schemes with a target whose code no run measured (`incomplete_targets/2`)."
  def incomplete_schemes(project_id, runs) do
    project_id |> incomplete_targets(runs) |> Map.keys() |> Enum.sort()
  end

  @doc """
  The test targets of each run that executed code the run couldn't measure,
  as `{test_run_id, test target}` pairs: the run is no source of coverage
  for them (`Tuist.Tests.Coverage.TargetSources`, `Tuist.Tests.Coverage.TestSources`).
  """
  def uninstrumented_test_targets(_project_id, []), do: MapSet.new()

  def uninstrumented_test_targets(project_id, runs) do
    runs
    |> Enum.group_by(&Map.get(&1, :build_system), & &1.test_run_id)
    |> Enum.map(fn
      {"xcode", run_ids} -> Xcode.uninstrumented_test_targets(project_id, run_ids)
      {_build_system, _run_ids} -> MapSet.new()
    end)
    |> Enum.reduce(MapSet.new(), &MapSet.union/2)
  end

  defp uninstrumented_targets(project_id, runs) do
    runs
    |> Enum.group_by(&Map.get(&1, :build_system), & &1.test_run_id)
    |> Enum.flat_map(fn
      {"xcode", run_ids} -> Xcode.uninstrumented_targets(project_id, run_ids)
      {_build_system, _run_ids} -> []
    end)
    |> Map.new()
  end
end
