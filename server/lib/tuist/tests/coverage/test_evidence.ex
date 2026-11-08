defmodule Tuist.Tests.Coverage.TestEvidence do
  @moduledoc """
  Each test's evidence at a checkout: the one place coverage carry
  (`Tuist.Tests.Coverage.Reported`) and test impact analysis
  (`Tuist.TestImpactAnalysis.Input`) get it from. The callers differ only in
  the blobs they hand in: a commit's listing for carry, and for selection
  the baseline's listing overlaid with the changed files.

  A test's versions are what `Tuist.Tests.Coverage.TestSources` recorded
  for it, on any branch and at any commit. A version holds at the checkout
  when the checkout reproduces every blob it executed, wherever it ran, so
  versions aren't bounded by commit: `coverage_test_sources` keeps one row
  per version, which names whichever run had it last.

  Replacing how evidence is chosen means rewriting this module only.
  """
  alias Tuist.Tests.Coverage.TestSources

  @doc """
  Each test's evidence at the checkout, as `%{test_case_id => %{newest:,
  reproduced:}}`: `newest` its latest version, `reproduced` the latest one
  the checkout reproduces, nil when it reproduces none. Tests without
  versions are left out. A version holds `paths`, `unlined_paths`,
  `passed`, `run_id`, `sha` and `ran_at`.

  `blobs` is handed every path the versions executed and returns the
  checkout's blob for each it knows, as `%{path => blob}`.
  """
  def lookup(project_id, repository_id, test_case_ids, blobs) do
    versions = TestSources.versions(project_id, repository_id, test_case_ids)
    paths = versions |> Map.values() |> Enum.concat() |> Enum.flat_map(& &1.paths) |> Enum.uniq()
    resolve(versions, blobs.(paths))
  end

  @doc """
  `lookup/4` over versions already read, `%{test_case_id => [version]}`,
  and the checkout's blobs, `%{path => blob}`.
  """
  def resolve(versions_by_test, blobs) do
    versions_by_test
    |> Enum.reject(fn {_test_case_id, versions} -> versions == [] end)
    |> Map.new(fn {test_case_id, versions} ->
      {test_case_id,
       %{
         newest: Enum.max_by(versions, &ran_at/1, DateTime),
         reproduced: versions |> Enum.filter(&reproduced?(&1, blobs)) |> Enum.max_by(&ran_at/1, DateTime, fn -> nil end)
       }}
    end)
  end

  defp reproduced?(version, blobs) do
    Enum.all?(version.paths, &is_binary(blobs[&1])) and
      TestSources.fingerprint(Enum.map(version.paths, &{&1, blobs[&1]})) == version.fingerprint
  end

  defp ran_at(%{ran_at: %DateTime{} = ran_at}), do: ran_at
  defp ran_at(%{ran_at: %NaiveDateTime{} = ran_at}), do: DateTime.from_naive!(ran_at, "Etc/UTC")
end
