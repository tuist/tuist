defmodule TuistTestSupport.Fixtures.TestSelectionFixtures do
  @moduledoc """
  Fixtures for coverage-based test selection: impact runs with the tests
  they selected, their diffs, and the baseline runs whose tests the skipped
  ones are derived from.
  """
  alias Tuist.IngestRepo
  alias Tuist.TestImpactAnalysis.Run
  alias Tuist.TestImpactAnalysis.RunTest
  alias Tuist.TestImpactAnalysis.Storage
  alias Tuist.Tests.CoverageRun
  alias TuistTestSupport.Fixtures.RunsFixtures

  @doc """
  Inserts an impact run for `project_id` with the given `selected` tests
  (maps over a selected test's fields; `name` at least) and returns it. The
  selected count is derived from them. `skipped_count` (all skipped tests,
  those in unchanged modules included) defaults to the `unaffected` rule's
  skips in `rule_trace`, else 0.
  """
  def run_fixture(attrs \\ []) do
    project_id = Keyword.fetch!(attrs, :project_id)
    id = Keyword.get(attrs, :id, UUIDv7.generate())
    inserted_at = Keyword.get(attrs, :inserted_at, NaiveDateTime.utc_now())
    commit_sha = Keyword.get(attrs, :commit_sha, "a1b2c3d4e5f6")
    outcome = Keyword.get(attrs, :outcome, "selected")

    selected =
      attrs
      |> Keyword.get(:selected, [])
      |> Enum.map(fn test ->
        Map.merge(
          %{
            test_impact_run_id: id,
            project_id: project_id,
            test_case_id: UUIDv7.generate(),
            module_name: "AppTests",
            suite_name: "AppTests",
            reason: "impacted",
            matched_path: "",
            inserted_at: inserted_at
          },
          test
        )
      end)

    rule_trace = Keyword.get(attrs, :rule_trace, [])

    unaffected =
      Enum.find_value(rule_trace, 0, fn entry -> if entry.rule == "unaffected", do: entry.skipped end)

    skipped_count = Keyword.get(attrs, :skipped_count, unaffected)

    run =
      struct(Run, %{
        id: id,
        project_id: project_id,
        inserted_at: inserted_at,
        head_sha: Keyword.get(attrs, :head_sha, commit_sha),
        commit_sha: commit_sha,
        baseline_sha: Keyword.get(attrs, :baseline_sha, "0f0f0f0f0f0f"),
        git_branch: Keyword.get(attrs, :git_branch, "feature/search"),
        dirty: false,
        strategy: "coverage",
        build_system: "xcode",
        platform: Keyword.get(attrs, :platform, "ios"),
        build_context:
          Keyword.get(attrs, :build_context, %{"scheme" => "App", "destination" => "iPhone 17 Pro · iOS 26.1"}),
        requested_modules: Keyword.get(attrs, :requested_modules, []),
        outcome: outcome,
        reason: Keyword.get(attrs, :reason, ""),
        matched_path: Keyword.get(attrs, :matched_path, ""),
        rules_version: Keyword.get(attrs, :rules_version, "1"),
        rule_trace: Enum.map(rule_trace, &{&1.rule, &1.selected, &1.skipped, &1.verdict}),
        requested_count: if(outcome == "fallback", do: 0, else: length(selected) + skipped_count),
        selected_count: if(outcome == "fallback", do: 0, else: length(selected)),
        skipped_count: if(outcome == "fallback", do: 0, else: skipped_count)
      })

    {:ok, _} = IngestRepo.insert(run)
    if selected != [], do: IngestRepo.insert_all(RunTest, selected)

    {:ok, run} = Storage.get_run(project_id, id)
    run
  end

  @doc """
  Stores the diff between `baseline_sha` and the checked-out `commit_sha`
  with the given `changed_files` (maps with `path` at least).
  """
  def diff_fixture(attrs \\ []) do
    changed_files =
      attrs
      |> Keyword.get(:changed_files, [])
      |> Enum.map(&Map.merge(%{status: "modified", blob: "", affected_modules: []}, &1))

    :ok =
      Storage.put_diff(%{
        project_id: Keyword.fetch!(attrs, :project_id),
        commit_sha: Keyword.get(attrs, :commit_sha, "a1b2c3d4e5f6"),
        baseline_sha: Keyword.get(attrs, :baseline_sha, "0f0f0f0f0f0f"),
        changed_files: changed_files,
        changed_files_count: Keyword.get(attrs, :changed_files_count)
      })
  end

  @doc """
  Inserts the baseline run of `baseline_sha`: a test run that reported
  coverage for `scheme`, with a test case run per test in `tests` (maps
  with `test_case_id` and `name` at least). Returns the test run.
  """
  def baseline_fixture(attrs \\ []) do
    project_id = Keyword.fetch!(attrs, :project_id)
    baseline_sha = Keyword.get(attrs, :baseline_sha, "0f0f0f0f0f0f")
    scheme = Keyword.get(attrs, :scheme, "App")

    {:ok, test_run} =
      RunsFixtures.test_fixture(
        project_id: project_id,
        git_commit_sha: baseline_sha,
        scheme: scheme,
        git_branch: "main",
        test_modules: []
      )

    for test <- Keyword.get(attrs, :tests, []) do
      RunsFixtures.test_case_run_fixture(
        Keyword.merge(
          [project_id: project_id, test_run_id: test_run.id, git_commit_sha: baseline_sha, scheme: scheme],
          Map.to_list(test)
        )
      )
    end

    IngestRepo.insert_all(CoverageRun, [
      %{
        project_id: project_id,
        test_run_id: test_run.id,
        scheme: scheme,
        git_commit_sha: baseline_sha,
        covered_lines: 1,
        executable_lines: 2,
        version: 1,
        inserted_at: NaiveDateTime.utc_now()
      }
    ])

    test_run
  end
end
