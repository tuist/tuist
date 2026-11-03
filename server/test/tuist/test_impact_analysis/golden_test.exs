defmodule Tuist.TestImpactAnalysis.GoldenTest do
  @moduledoc """
  Drives the pipeline from the coverage test selection test bed's
  `golden.json` (`cli/Tests/Fixtures/CoverageTestSelection`): for each
  scenario the server decides, it records the scenario's runs as versions
  over a simulated tree, applies the rules to the checkout's changed files
  and the targets left after hash pruning, and compares every decision with
  the golden entry.

  Hash pruning happens in the CLI before the server sees anything, so the
  tests of `hash.skipped` targets are out of scope. Scenarios decided before
  the pipeline runs are checked to be fallbacks only (`@decided_elsewhere`).
  """
  use ExUnit.Case, async: true

  alias Tuist.GitHistory
  alias Tuist.TestImpactAnalysis
  alias Tuist.TestImpactAnalysis.Input
  alias Tuist.Tests.Coverage.TestSources

  @golden_path Path.expand("../../../../cli/Tests/Fixtures/CoverageTestSelection/golden.json", __DIR__)
  @external_resource @golden_path
  @golden @golden_path |> File.read!() |> JSON.decode!()

  @decided_elsewhere %{
    "default_branch" => "the baseline request answers excluded_branch before any diff",
    "window_over_cap" => "baseline resolution (step 3) finds no baseline within 20 measured commits",
    "no_baseline" => "baseline resolution (step 3) finds no baseline",
    "diff_too_large" => "the runs endpoint (step 5) records it from changed_files_count before the rules run"
  }

  # The files scenarios.sh edits at the runs a scenario records after the
  # baseline, which golden.json doesn't list.
  @run_edits Map.new(
               [{"run/carried-evidence/1", ["Core/Sources/Money.swift"]}] ++
                 for(
                   n <- 1..21,
                   do: {"run/evidence-window/#{String.pad_leading("#{n}", 2, "0")}", ["Core/Sources/Discount.swift"]}
                 )
             )

  # The files a checkout edits itself, when not all of its changed files:
  # carried_evidence's Money.swift is as run/carried-evidence/1 left it.
  @checkout_edits %{"carried_evidence" => ["Core/Sources/Discount.swift"]}

  for scenario <- @golden["scenarios"],
      {variant, scenario} <- [
        {nil, scenario} | for({v, o} <- scenario["variants"] || %{}, do: {v, Map.merge(scenario, o)})
      ] do
    name = if variant, do: "#{scenario["name"]} (#{variant})", else: scenario["name"]
    @scenario scenario

    if reason = @decided_elsewhere[scenario["name"]] do
      test "#{name} is a fallback decided outside the pipeline: #{reason}" do
        assert @scenario["outcome"] == "fallback"
      end
    else
      test name do
        assert_golden(@scenario)
      end
    end
  end

  test "every fallback the pipeline doesn't decide is accounted for" do
    for scenario <- @golden["scenarios"],
        scenario["outcome"] == "fallback",
        scenario["reason"] != "tracked_file_changed" do
      assert Map.has_key?(@decided_elsewhere, scenario["name"]), "#{scenario["name"]} falls back outside the pipeline"
    end
  end

  defp assert_golden(scenario) do
    result = scenario |> checkout_input() |> TestImpactAnalysis.run()

    case scenario["outcome"] do
      "selected" ->
        assert result.outcome == :selected
        assert result.decisions == expected_decisions(scenario)

      "fallback" ->
        assert {result.outcome, to_string(result.reason), result.matched_path} ==
                 {:fallback, scenario["reason"], scenario["matched_path"]}
    end
  end

  defp expected_decisions(scenario) do
    run =
      for {id, %{"reason" => reason} = decision} <- scenario["run"],
          decision["known_to_server"] != false,
          into: %{},
          do:
            {id, %{decision: :selected, reason: String.to_existing_atom(reason), matched_path: decision["matched_path"]}}

    skip =
      Map.new(scenario["skip"], fn {id, reason} ->
        {id, %{decision: :skipped, reason: String.to_existing_atom(reason), matched_path: nil}}
      end)

    Map.merge(run, skip)
  end

  defp checkout_input(scenario) do
    {versions, tree} = record_runs(scenario)
    edits = Map.get(@checkout_edits, scenario["name"], Enum.map(scenario["changed_files"], & &1["path"]))
    tree = edit(tree, edits, scenario["checkout"]["ref"], scenario["changed_files"])
    input(scenario, scope(scenario), versions, tree)
  end

  # The baseline runs every test; each later run applies the pipeline to its
  # own diff against the baseline and records versions for the tests it ran.
  defp record_runs(%{"runs" => [baseline | later]} = scenario) do
    failing = String.split(get_in(baseline, ["env", "TEST_RUNNER_TESTBED_FAILING_TESTS"]) || "", ",", trim: true)
    tree = baseline_tree()
    versions = record(%{}, Map.keys(evidence()["tests"]), tree, "baseline", 0, failing)

    later
    |> Enum.with_index(1)
    |> Enum.reduce({versions, tree}, fn {%{"ref" => ref}, index}, {versions, tree} ->
      tree = edit(tree, Map.fetch!(@run_edits, ref), ref, scenario["changed_files"])
      changed = changed_since_baseline(tree, scenario["changed_files"])
      result = TestImpactAnalysis.run(input(%{"changed_files" => changed}, all_tests(), versions, tree))
      ran = for {id, %{decision: :selected}} <- result.decisions, do: id
      {record(versions, ran, tree, ref, index, []), tree}
    end)
  end

  defp record(versions, test_ids, tree, sha, index, failing) do
    for id <- test_ids, paths = evidence_paths(id), paths != [], reduce: versions do
      versions ->
        pairs = Enum.map(paths, &{&1, Map.fetch!(tree, &1)})

        version = %{
          fingerprint: TestSources.fingerprint(pairs),
          paths: paths,
          unlined_paths: [],
          passed: not Enum.any?(failing, &String.ends_with?(id, "/" <> &1)),
          run_id: sha,
          sha: sha,
          ran_at: DateTime.add(~U[2026-11-01 00:00:00.000000Z], index, :hour)
        }

        Map.update(versions, id, [version], &[version | &1])
    end
  end

  defp input(scenario, tests, versions, tree) do
    changed_files =
      for file <- scenario["changed_files"] do
        %{
          path: file["path"],
          status: file["status"],
          blob: if(file["status"] != "D", do: Map.get(tree, file["path"])),
          affected_modules: file["affected_modules"]
        }
      end

    Input.new(%{
      tests: tests,
      changed_files: changed_files,
      changed_files_count: scenario["changed_files_count"] || length(changed_files),
      tracked_file_globs: GitHistory.settings(nil).tracked_file_globs,
      baseline_blobs: baseline_tree(),
      versions: versions,
      target_evidence: evidence()["targets"],
      test_paths: evidence()["test_files"],
      evidence_paths: all_evidence_paths(),
      flaky: []
    })
  end

  defp scope(scenario) do
    skipped = get_in(scenario, ["hash", "skipped"]) || []
    Enum.reject(all_tests(), &(&1.module_name in skipped))
  end

  defp all_tests do
    for {module_name, %{"tests" => tests}} <- @golden["test_targets"], test <- tests do
      [suite_name, name] = String.split(test, "/")
      %{test_case_id: "#{module_name}/#{test}", module_name: module_name, suite_name: suite_name, name: name}
    end
  end

  # What a test and its suite's setup executed at the baseline.
  defp evidence_paths(id) do
    suite = id |> String.split("/") |> Enum.take(2) |> Enum.join("/")
    Enum.uniq(Enum.sort(Map.get(evidence()["tests"], id, []) ++ Map.get(evidence()["suites"], suite, [])))
  end

  defp baseline_tree, do: Map.new(all_evidence_paths(), &{&1, "#{&1}@baseline"})

  defp all_evidence_paths do
    %{"tests" => tests, "suites" => suites, "targets" => targets, "test_files" => test_files} = evidence()
    [tests, suites, targets] |> Enum.flat_map(&Map.values/1) |> Enum.concat() |> Enum.concat(test_files) |> Enum.uniq()
  end

  defp evidence, do: @golden["baseline_evidence"]

  defp edit(tree, paths, ref, changed_files) do
    deleted = for %{"path" => path, "status" => "D"} <- changed_files, do: path

    Enum.reduce(paths, tree, fn path, tree ->
      if path in deleted, do: Map.delete(tree, path), else: Map.put(tree, path, "#{path}@#{ref}")
    end)
  end

  # A run's diff against the baseline, classified as the checkout's diff
  # classifies the same paths.
  defp changed_since_baseline(tree, checkout_files) do
    baseline = baseline_tree()

    for {path, blob} <- tree, Map.get(baseline, path) != blob do
      checkout_files |> Enum.find(%{}, &(&1["path"] == path)) |> Map.merge(%{"path" => path, "status" => "M"})
    end
  end
end
