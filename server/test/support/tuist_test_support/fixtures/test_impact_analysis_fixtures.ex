defmodule TuistTestSupport.Fixtures.TestImpactAnalysisFixtures do
  @moduledoc """
  Hand-built inputs for the test impact analysis rules
  (`Tuist.TestImpactAnalysis.Input`): tests, their versions over the blobs
  they executed, and changed files.
  """

  alias Tuist.TestImpactAnalysis.Input
  alias Tuist.Tests.Coverage.TestEvidence
  alias Tuist.Tests.Coverage.TestSources

  @doc "A test in scope, identified as `Module/Suite/name`."
  def test_case(identifier) do
    [module_name, suite_name, name] = String.split(identifier, "/")
    %{test_case_id: identifier, module_name: module_name, suite_name: suite_name, name: name}
  end

  @doc """
  A version of a test that executed `blobs` (`%{path => blob}`). `opts`:
  `:passed` (default true), `:ran_at` (default a fixed time), `:run_id`, and
  `:sha`, `"baseline"` by default.
  """
  def version(blobs, opts \\ []) do
    pairs = Enum.to_list(blobs)

    %{
      fingerprint: TestSources.fingerprint(pairs),
      paths: pairs |> Enum.map(&elem(&1, 0)) |> Enum.sort(),
      unlined_paths: [],
      passed: Keyword.get(opts, :passed, true),
      run_id: Keyword.get(opts, :run_id, "run"),
      sha: Keyword.get(opts, :sha, "baseline"),
      ran_at: Keyword.get(opts, :ran_at, ~U[2026-11-01 00:00:00.000000Z]),
      blobs: blobs
    }
  end

  @doc "A changed file, modified by default, with its new blob."
  def changed(path, opts \\ []) do
    %{
      path: path,
      status: Keyword.get(opts, :status, "M"),
      blob: Keyword.get(opts, :blob, "new-" <> path),
      affected_modules: Keyword.get(opts, :affected_modules)
    }
  end

  @doc """
  An input whose tests are given by identifier, with `versions` keyed by
  identifier too, resolved through `Tuist.Tests.Coverage.TestEvidence`
  against the checkout's blobs: `baseline_blobs`, by default the blobs the
  baseline's versions executed, overlaid with the changed files.
  """
  def input(attrs) do
    attrs = Map.new(attrs)
    versions = Map.get(attrs, :versions, %{})

    baseline_blobs =
      Map.get_lazy(attrs, :baseline_blobs, fn ->
        Map.new(for {_id, test_versions} <- versions, %{sha: "baseline"} = v <- test_versions, pair <- v.blobs, do: pair)
      end)

    versions = Map.new(versions, fn {id, test_versions} -> {id, Enum.map(test_versions, &Map.delete(&1, :blobs))} end)
    blobs = Input.checkout_blobs(baseline_blobs, Map.get(attrs, :changed_files, []))

    attrs
    |> Map.drop([:versions, :baseline_blobs])
    |> Map.update(:tests, [], fn tests -> Enum.map(tests, &test_case/1) end)
    |> Map.put(:evidence, TestEvidence.resolve(versions, blobs))
    |> Input.new()
  end
end
