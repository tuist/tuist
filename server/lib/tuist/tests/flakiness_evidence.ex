defmodule Tuist.Tests.FlakinessEvidence do
  @moduledoc """
  Holds correlated runner crashes out of automatic test-health decisions.

  This is a conservative evidence guard, not a diagnosis of the crash. A burst
  of crashes without measured duration across modules cannot reliably identify
  individual flaky tests. Keep the original outcomes and diagnostics for investigation.

  Require at least twenty distinct cases in two modules in one Xcode report.
  This deliberately leaves small or single-module crashes eligible: without
  broader correlation, a crash may be caused by an individual test.
  """

  @minimum_crashes 20
  @minimum_modules 2
  @crash_messages [
    "Crash: xctest",
    "Crash: xctest at static xctest.main()",
    "Test crashed with signal trap."
  ]

  def annotate(attrs) do
    modules = Map.get(attrs, :test_modules, [])

    candidates =
      modules
      |> Enum.reduce(%{}, fn module, candidates ->
        Enum.reduce(Map.get(module, :test_cases, []), candidates, fn test_case, acc ->
          candidate? = crash_candidate?(test_case)
          Map.update(acc, identity(module, test_case), candidate?, &(&1 and candidate?))
        end)
      end)
      |> Enum.filter(fn {_identity, candidate?} -> candidate? end)
      |> Enum.map(&elem(&1, 0))

    module_count = candidates |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> length()

    excluded =
      if Map.get(attrs, :build_system, "xcode") == "xcode" and
           length(candidates) >= @minimum_crashes and module_count >= @minimum_modules do
        MapSet.new(candidates)
      else
        MapSet.new()
      end

    # Always overwrite this server-owned decision, including when a caller
    # supplies a flag or the report contains no correlated crash evidence.
    Map.put(attrs, :test_modules, Enum.map(modules, &annotate_module(&1, excluded)))
  end

  defp annotate_module(module, excluded) do
    Map.update(module, :test_cases, [], fn test_cases ->
      Enum.map(test_cases, fn test_case ->
        Map.put(test_case, :is_flakiness_excluded, MapSet.member?(excluded, identity(module, test_case)))
      end)
    end)
  end

  defp identity(module, test_case) do
    {Map.get(module, :name), Map.get(test_case, :test_suite_name) || "", Map.get(test_case, :name)}
  end

  defp crash_candidate?(test_case) do
    observations = [test_case | Map.get(test_case, :arguments, [])]
    failures = Enum.flat_map(observations, &Map.get(&1, :failures, []))

    failure_observations =
      Enum.filter(observations, fn observation ->
        Map.get(observation, :status) == "failure" or failed_repetitions(observation) != []
      end)

    failure_observations != [] and Enum.all?(failure_observations, &unmeasured_failure?/1) and
      failures != [] and Enum.all?(failures, &runner_crash?/1)
  end

  defp unmeasured_failure?(observation) do
    # Remote xcresult parsing omits unavailable timings; the CLI encodes them as zero.
    case failed_repetitions(observation) do
      [] -> Map.get(observation, :duration) in [nil, 0]
      repetitions -> Enum.all?(repetitions, &(Map.get(&1, :duration) in [nil, 0]))
    end
  end

  defp failed_repetitions(observation) do
    observation |> Map.get(:repetitions, []) |> Enum.filter(&(Map.get(&1, :status) == "failure"))
  end

  defp runner_crash?(failure) do
    Map.get(failure, :message) in @crash_messages and
      Map.get(failure, :path) in [nil, ""] and Map.get(failure, :line_number) in [nil, 0]
  end
end
