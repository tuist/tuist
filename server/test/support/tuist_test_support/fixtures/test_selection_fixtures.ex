defmodule TuistTestSupport.Fixtures.TestSelectionFixtures do
  @moduledoc """
  Fixtures for coverage-based test selection: selection runs with their
  tests, and test impacts with their changed files and affected tests.
  """
  alias Tuist.IngestRepo
  alias Tuist.Tests.TestImpact
  alias Tuist.Tests.TestImpactChangedFile
  alias Tuist.Tests.TestImpactTest
  alias Tuist.Tests.TestSelectionRun
  alias Tuist.Tests.TestSelectionTest

  @doc """
  Inserts a selection run for `project_id` with the given `tests` (maps over
  a test's fields; `decision` and `name` at least) and returns it. Counts
  are derived from the tests.
  """
  def run_fixture(attrs \\ []) do
    project_id = Keyword.fetch!(attrs, :project_id)
    id = Keyword.get(attrs, :id, UUIDv7.generate())
    inserted_at = Keyword.get(attrs, :inserted_at, NaiveDateTime.utc_now())

    tests =
      attrs
      |> Keyword.get(:tests, [])
      |> Enum.map(fn test ->
        Map.merge(
          %{
            project_id: project_id,
            selection_run_id: id,
            test_case_id: UUIDv7.generate(),
            module_name: "AppTests",
            suite_name: "AppTests",
            name: "",
            shard_index: 0,
            reason: if(test[:decision] == "selected", do: "impacted", else: "unaffected"),
            matched_path: "",
            estimated_duration_ms: 100,
            inserted_at: inserted_at
          },
          test
        )
      end)

    {selected, skipped} = Enum.split_with(tests, &(&1.decision == "selected"))

    run = %{
      id: id,
      project_id: project_id,
      idempotency_key: Keyword.get(attrs, :idempotency_key, "github:1:test"),
      git_commit_sha: Keyword.get(attrs, :git_commit_sha, "a1b2c3d4e5f6"),
      git_branch: Keyword.get(attrs, :git_branch, "feature/search"),
      baseline_sha: Keyword.get(attrs, :baseline_sha, "0f0f0f0f0f0f"),
      scheme: Keyword.get(attrs, :scheme, "App"),
      test_plan: Keyword.get(attrs, :test_plan, ""),
      destination: Keyword.get(attrs, :destination, "iPhone 17 Pro · iOS 26.1"),
      requested_targets: tests |> Enum.map(& &1.module_name) |> Enum.uniq() |> Enum.sort(),
      mode: Keyword.get(attrs, :mode, "dry_run"),
      shard_count: Keyword.get(attrs, :shard_count, 1),
      shard_plan_id: nil,
      test_run_id: Keyword.get(attrs, :test_run_id),
      ci_provider: "github",
      ci_run_id: Keyword.get(attrs, :ci_run_id, "1"),
      ci_job_id: Keyword.get(attrs, :ci_job_id, "test"),
      requested_count: length(tests),
      selected_count: length(selected),
      skipped_count: length(skipped),
      missed_count: Keyword.get(attrs, :missed_count, 0),
      skipped_duration: skipped |> Enum.map(& &1.estimated_duration_ms) |> Enum.sum(),
      fallback_reason: Keyword.get(attrs, :fallback_reason, ""),
      inserted_at: inserted_at,
      updated_at: inserted_at
    }

    IngestRepo.insert_all(TestSelectionRun, [run])
    if tests != [], do: IngestRepo.insert_all(TestSelectionTest, tests)

    struct(TestSelectionRun, run)
  end

  @doc """
  Inserts the test impact of `head_sha` against `baseline_sha` with the given
  `changed_files` (maps with `path` at least) and `tests` (maps with
  `test_case_id`, `name` and `reason` at least), and returns it.
  """
  def impact_fixture(attrs \\ []) do
    project_id = Keyword.fetch!(attrs, :project_id)
    head = Keyword.get(attrs, :head_sha, "a1b2c3d4e5f6")
    baseline = Keyword.get(attrs, :baseline_sha, "0f0f0f0f0f0f")
    inserted_at = Keyword.get(attrs, :inserted_at, NaiveDateTime.utc_now())
    key = %{project_id: project_id, head_sha: head, baseline_sha: baseline, inserted_at: inserted_at}

    files =
      attrs
      |> Keyword.get(:changed_files, [])
      |> Enum.map(&Map.merge(Map.merge(key, %{status: "modified", kind: "source", impacted_tests_count: 0}), &1))

    tests =
      attrs
      |> Keyword.get(:tests, [])
      |> Enum.map(
        &Map.merge(
          Map.merge(key, %{module_name: "AppTests", suite_name: "AppTests", matched_path: ""}),
          &1
        )
      )

    impact =
      Map.merge(key, %{
        git_branch: Keyword.get(attrs, :git_branch, "feature/search"),
        changed_files_count: length(files),
        impacted_tests_count: length(tests)
      })

    IngestRepo.insert_all(TestImpact, [impact])
    if files != [], do: IngestRepo.insert_all(TestImpactChangedFile, files)
    if tests != [], do: IngestRepo.insert_all(TestImpactTest, tests)

    struct(TestImpact, impact)
  end
end
